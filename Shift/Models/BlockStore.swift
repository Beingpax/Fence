import Foundation
import Observation
import os.log

/// Owns every block, their persistence, and the rules about what the user is allowed
/// to change while a lock is engaged.
///
/// Reads are cheap and synchronous because the collection is small and lives in memory.
/// Writes are debounced and encoded off the main actor, so typing in the block editor
/// never touches the disk on the main thread.
@MainActor
@Observable
final class BlockStore {
    nonisolated private static let log = Logger(subsystem: "com.beingpax.Shift", category: "BlockStore")
    nonisolated private static let saveQueue = DispatchQueue(label: "com.beingpax.Shift.blockStore", qos: .utility)

    private(set) var blocks: [Block] = []

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    // MARK: Storage

    /// Nonisolated: the writer runs off the main actor, so this must be reachable there.
    nonisolated private static var fileURL: URL {
        GuardState.supportDirectory.appending(path: "blocks.json", directoryHint: .notDirectory)
    }

    init(loadFromDisk: Bool = true) {
        if loadFromDisk {
            blocks = Self.loadFromDisk()
            resolveRestartLocks()
            expireFinishedRuns()
        }
    }

    nonisolated private static func loadFromDisk() -> [Block] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([Block].self, from: data)
        } catch {
            log.error("Could not decode blocks: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Coalesces rapid edits before enqueuing a snapshot.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.enqueueSave()
        }
    }

    /// Enqueues an immediate save for changes such as starting a break or a locked run.
    func saveNow() {
        saveTask?.cancel()
        enqueueSave()
    }

    private func enqueueSave() {
        let snapshot = blocks
        Self.saveQueue.async { Self.write(snapshot) }
    }

    nonisolated private static func write(_ blocks: [Block]) {
        do {
            try FileManager.default.createDirectory(
                at: GuardState.supportDirectory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(blocks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Could not save blocks: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Queries

    var activeBlocks: [Block] { blocks.filter { $0.isActive() } }

    var hasLockedBlock: Bool { blocks.contains { $0.lock.isLocked() } }

    /// The furthest-out lock deadline, which is what the watchdog needs to know.
    var lockedUntil: Date? {
        let deadlines = blocks.compactMap { block -> Date? in
            if block.lock.engagedUntilRestart { return Date.distantFuture }
            return block.lock.isLocked() ? block.lock.engagedUntil : nil
        }
        return deadlines.max()
    }

    func block(id: UUID) -> Block? { blocks.first { $0.id == id } }

    // MARK: Mutation

    func add(_ block: Block) {
        blocks.append(block)
        scheduleSave()
    }

    /// Edits are refused while the block is locked, so a lock can't be edited away.
    @discardableResult
    func update(_ block: Block) -> Bool {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return false }
        let current = blocks[index]
        if current.lock.isLocked(), !isSafeEditWhileLocked(from: current, to: block) {
            return false
        }
        var updated = block
        updated.isEnabled = current.isEnabled
        updated.manualRunEndsAt = updated.schedule.isManual ? current.manualRunEndsAt : nil
        if updated.schedule.isManual && !current.schedule.isManual {
            updated.isEnabled = false
            updated.manualRunEndsAt = nil
        }
        updated.stats = current.stats
        updated.lock.engagedUntil = current.lock.engagedUntil
        updated.lock.engagedUntilRestart = current.lock.engagedUntilRestart
        updated.lock.engagedAtBootTime = current.lock.engagedAtBootTime
        updated.breaks.currentBreakEndsAt = current.breaks.currentBreakEndsAt
        updated.breaks.breaksTakenToday = current.breaks.breaksTakenToday
        updated.breaks.lastResetDay = current.breaks.lastResetDay
        blocks[index] = updated
        scheduleSave()
        return true
    }

    /// While locked, the only edits allowed are ones that make the block stricter or
    /// are purely cosmetic. Anything that could weaken it is refused.
    private func isSafeEditWhileLocked(from existing: Block, to proposed: Block) -> Bool {
        guard existing.schedule == proposed.schedule, existing.goal == proposed.goal else { return false }
        guard existing.lock.method == proposed.lock.method else { return false }
        guard existing.breaks.isEnabled == proposed.breaks.isEnabled,
              existing.breaks.minutes == proposed.breaks.minutes,
              existing.breaks.allowance == proposed.breaks.allowance
        else { return false }
        // Entries may be added but never removed.
        let grew = { (old: [String], new: [String]) in Set(old).isSubset(of: Set(new)) }
        guard grew(existing.list.hosts, proposed.list.hosts),
              grew(existing.list.paths, proposed.list.paths),
              grew(existing.list.apps, proposed.list.apps)
        else { return false }
        return true
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return false }
        guard !blocks[index].lock.isLocked() else { return false }
        blocks.remove(at: index)
        scheduleSave()
        return true
    }

    func canMove(id: UUID, by offset: Int) -> Bool {
        movableIndex(for: id, offset: offset) != nil
    }

    func move(id: UUID, by offset: Int) {
        guard let index = movableIndex(for: id, offset: offset) else { return }
        blocks.swapAt(index, index + offset)
        scheduleSave()
    }

    private func movableIndex(for id: UUID, offset: Int) -> Int? {
        guard offset == -1 || offset == 1, let index = blocks.firstIndex(where: { $0.id == id }),
              blocks.indices.contains(index + offset),
              !blocks[index].lock.isLocked(), !blocks[index + offset].lock.isLocked()
        else { return nil }
        return index
    }

    // MARK: Turning blocks on and off

    enum ToggleResult: Equatable {
        case changed
        case refusedLocked(String)
        case needsRandomString
        case needsTimedStart
    }

    /// Switching a block on engages its lock. That is the whole point of a lock: you
    /// choose the terms while you're thinking clearly, and they bind afterwards.
    @discardableResult
    func setEnabled(_ enabled: Bool, for id: UUID, now: Date = Date()) -> ToggleResult {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return .changed }
        var block = blocks[index]
        guard enabled != block.isEnabled else { return .changed }

        if !enabled, block.lock.isLocked(at: now) {
            return .refusedLocked(block.lock.statusText(at: now))
        }

        if !enabled, block.lock.method == .randomString {
            return .needsRandomString
        }

        if enabled, block.schedule.isManual { return .needsTimedStart }
        block.isEnabled = enabled

        if enabled {
            engageLock(on: &block, now: now)
        } else {
            block.lock.engagedUntil = nil
            block.lock.engagedUntilRestart = false
            block.lock.engagedAtBootTime = nil
            block.manualRunEndsAt = nil
            block.breaks.currentBreakEndsAt = nil
        }

        blocks[index] = block
        saveNow()
        return .changed
    }

    private func engageLock(on block: inout Block, now: Date) {
        switch block.lock.method {
        case .none, .randomString:
            break
        case .duration, .untilTime:
            block.lock.engagedUntil = block.lock.engagementDeadline(from: now)
        case .restart:
            block.lock.engagedUntilRestart = true
            block.lock.engagedAtBootTime = Self.bootTime()
        }
    }

    /// Unlock path for the random-string method. The caller shows the challenge and
    /// passes back what the user typed.
    @discardableResult
    func unlockWithString(_ typed: String, challenge: String, for id: UUID) -> Bool {
        guard typed == challenge else { return false }
        guard let index = blocks.firstIndex(where: { $0.id == id }),
              blocks[index].isEnabled, blocks[index].lock.method == .randomString,
              !blocks[index].lock.isLocked()
        else { return false }
        blocks[index].isEnabled = false
        blocks[index].manualRunEndsAt = nil
        blocks[index].lock.engagedUntil = nil
        blocks[index].lock.engagedUntilRestart = false
        blocks[index].breaks.currentBreakEndsAt = nil
        saveNow()
        return true
    }

    @discardableResult
    func startManualRun(id: UUID, minutes: Int, now: Date = Date()) -> Bool {
        guard minutes > 0, let index = blocks.firstIndex(where: { $0.id == id }) else { return false }
        var block = blocks[index]
        guard block.schedule.isManual, !block.isEnabled, !block.lock.isLocked(at: now) else { return false }

        block.isEnabled = true
        block.manualRunEndsAt = now.addingTimeInterval(TimeInterval(minutes) * 60)
        engageLock(on: &block, now: now)
        blocks[index] = block
        saveNow()
        return true
    }

    // MARK: Breaks

    @discardableResult
    func startBreak(id: UUID, now: Date = Date()) -> Bool {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return false }
        var block = blocks[index]
        guard block.isActive(at: now), block.breaks.start(at: now) else { return false }

        blocks[index] = block
        saveNow()
        return true
    }

    // MARK: Housekeeping

    /// A `.restart` lock is released only when the machine has genuinely rebooted.
    /// Comparing boot time is how we know, rather than trusting the app's own lifetime.
    private func resolveRestartLocks() {
        let currentBoot = Self.bootTime()
        var changed = false
        for index in blocks.indices where blocks[index].lock.engagedUntilRestart {
            guard let engagedBoot = blocks[index].lock.engagedAtBootTime else { continue }
            // Boot times drift by a second or two between samples; a real reboot moves them far.
            if abs(currentBoot.timeIntervalSince(engagedBoot)) > 60 {
                blocks[index].lock.engagedUntilRestart = false
                blocks[index].lock.engagedAtBootTime = nil
                blocks[index].isEnabled = false
                changed = true
            }
        }
        if changed { saveNow() }
    }

    /// Clears manual runs that finished while the app wasn't running.
    private func expireFinishedRuns() {
        let now = Date()
        var changed = false
        for index in blocks.indices {
            if retireTimedRun(&blocks[index], at: now) { changed = true }
        }
        if changed { saveNow() }
    }

    /// Called on the engine's tick to retire finished runs, breaks and locks.
    func tick(now: Date = Date()) {
        var changed = false
        for index in blocks.indices {
            var block = blocks[index]

            _ = retireTimedRun(&block, at: now)
            if let breakEnd = block.breaks.currentBreakEndsAt, breakEnd <= now {
                block.breaks.currentBreakEndsAt = nil
            }
            if let lockEnd = block.lock.engagedUntil, lockEnd <= now, !block.lock.engagedUntilRestart {
                block.lock.engagedUntil = nil
            }
            if block != blocks[index] {
                blocks[index] = block
                changed = true
            }
        }
        if changed { scheduleSave() }
    }

    private func retireTimedRun(_ block: inout Block, at date: Date) -> Bool {
        guard block.schedule.isManual, block.isEnabled, !block.lock.isLocked(at: date),
              block.manualRunEndsAt.map({ $0 <= date }) ?? true
        else { return false }
        block.manualRunEndsAt = nil
        block.isEnabled = false
        block.breaks.currentBreakEndsAt = nil
        return true
    }

    func recordTrigger(id: UUID, now: Date = Date()) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[index].stats.timesTriggered += 1
        blocks[index].stats.lastTriggered = now
        scheduleSave()
    }

    /// Boot time, derived from uptime. Stable across samples on the same boot.
    static func bootTime() -> Date {
        Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)
    }

    /// The challenge string for a random-string unlock.
    static func randomChallenge(length: Int) -> String {
        let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<max(8, length)).map { _ in alphabet.randomElement() ?? "x" })
    }
}
