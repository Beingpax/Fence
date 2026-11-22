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
    @ObservationIgnored private var unlockChallenges: [Block.ID: String] = [:]

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

    /// Drains queued writes and any debounced edits before a normal quit.
    func flushPendingSaves() {
        saveNow()
        Self.saveQueue.sync {}
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

    var lockedBlocks: [Block] { blocks.filter { $0.isLocked() } }
    var hasLockedBlock: Bool { blocks.contains { $0.isLocked() } }

    /// The furthest-out lock deadline, which is what the watchdog needs to know.
    var lockedUntil: Date? {
        let now = Date()
        let deadlines = blocks.compactMap { block -> Date? in
            if block.lock.engagedUntilRestart { return .distantFuture }
            if block.requiresUnlockChallenge(at: now) {
                return block.schedule.isManual ? block.manualRunEndsAt : .distantFuture
            }
            return block.lock.isLocked(at: now) ? block.lock.engagedUntil : nil
        }
        return deadlines.max()
    }

    func block(id: UUID) -> Block? { blocks.first { $0.id == id } }

    // MARK: Mutation

    func add(_ block: Block) {
        blocks.append(block)
        saveNow()
    }

    /// Edits are refused while the block is locked, so a lock can't be edited away.
    @discardableResult
    func update(_ block: Block, now: Date = Date()) -> Bool {
        guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return false }
        let current = blocks[index]
        if current.isLocked(at: now), !isSafeEditWhileLocked(from: current, to: block) {
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
        updated.lock.engagedBootSessionID = current.lock.engagedBootSessionID
        if updated.isEnabled && !updated.lock.hasSameSettings(as: current.lock) {
            engageLock(on: &updated, now: now)
        }
        updated.breaks.currentBreakEndsAt = current.breaks.currentBreakEndsAt
        updated.breaks.breaksTakenToday = current.breaks.breaksTakenToday
        updated.breaks.lastResetDay = current.breaks.lastResetDay
        blocks[index] = updated
        saveNow()
        return true
    }

    /// While locked, the only edits allowed are ones that make the block stricter or
    /// are purely cosmetic. Anything that could weaken it is refused.
    private func isSafeEditWhileLocked(from existing: Block, to proposed: Block) -> Bool {
        guard existing.schedule == proposed.schedule, existing.goal == proposed.goal else { return false }
        guard existing.lock.hasSameSettings(as: proposed.lock),
              existing.breaks.isEnabled == proposed.breaks.isEnabled
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
        guard !blocks[index].isLocked() else { return false }
        blocks.remove(at: index)
        scheduleSave()
        return true
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

        if !enabled, block.requiresUnlockChallenge(at: now) {
            return .needsRandomString
        }

        if enabled, block.schedule.isManual { return .needsTimedStart }
        block.isEnabled = enabled

        if enabled {
            engageLock(on: &block, now: now)
        } else {
            endRun(&block)
        }

        blocks[index] = block
        saveNow()
        return .changed
    }

    private func engageLock(on block: inout Block, now: Date) {
        clearEngagement(&block.lock)
        switch block.lock.method {
        case .none, .randomString:
            break
        case .duration, .untilTime:
            block.lock.engagedUntil = block.lock.engagementDeadline(from: now)
        case .restart:
            block.lock.engagedUntilRestart = true
            block.lock.engagedAtBootTime = Self.bootTime()
            block.lock.engagedBootSessionID = Self.bootSessionID
        }
    }

    private func clearEngagement(_ lock: inout BlockLock) {
        lock.engagedUntil = nil
        lock.engagedUntilRestart = false
        lock.engagedAtBootTime = nil
        lock.engagedBootSessionID = nil
    }

    private func endRun(_ block: inout Block) {
        unlockChallenges.removeValue(forKey: block.id)
        block.isEnabled = false
        block.manualRunEndsAt = nil
        block.breaks.currentBreakEndsAt = nil
        clearEngagement(&block.lock)
    }

    func createUnlockChallenge(for id: Block.ID) -> String? {
        guard let block = block(id: id), block.requiresUnlockChallenge() else { return nil }
        let challenge = Self.randomChallenge(length: block.lock.challengeLength)
        unlockChallenges[id] = challenge
        return challenge
    }

    @discardableResult
    func unlockWithString(_ typed: String, for id: Block.ID) -> Bool {
        guard let challenge = unlockChallenges[id], typed == challenge,
              let index = blocks.firstIndex(where: { $0.id == id }),
              blocks[index].requiresUnlockChallenge(), !blocks[index].lock.isLocked()
        else { return false }
        var block = blocks[index]
        endRun(&block)
        blocks[index] = block
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
    /// The boot session ID survives app relaunches and wall-clock changes.
    private func resolveRestartLocks() {
        let currentBoot = Self.bootTime()
        let bootSessionID = Self.bootSessionID
        var changed = false
        for index in blocks.indices where blocks[index].lock.engagedUntilRestart {
            var block = blocks[index]
            let restarted: Bool
            if let bootSessionID, let engagedSession = block.lock.engagedBootSessionID {
                restarted = bootSessionID != engagedSession
            } else if let engagedBoot = block.lock.engagedAtBootTime {
                restarted = abs(currentBoot.timeIntervalSince(engagedBoot)) > 60
            } else {
                restarted = false
            }

            if restarted {
                endRun(&block)
            } else if let bootSessionID, block.lock.engagedBootSessionID == nil {
                block.lock.engagedBootSessionID = bootSessionID
            }
            if block != blocks[index] {
                blocks[index] = block
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
            var block = blocks[index]
            if retireTimedRun(&block, at: now) {
                blocks[index] = block
                changed = true
            }
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
        endRun(&block)
        return true
    }

    func recordTrigger(id: UUID, now: Date = Date()) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[index].stats.timesTriggered += 1
        blocks[index].stats.lastTriggered = now
        scheduleSave()
    }

    private static let bootSessionID: String? = {
        var length = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &length, nil, 0) == 0, length > 1 else { return nil }
        var bytes = [CChar](repeating: 0, count: length)
        return bytes.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress,
                  sysctlbyname("kern.bootsessionuuid", base, &length, nil, 0) == 0
            else { return nil }
            return String(cString: base)
        }
    }()

    /// Boot time, derived from uptime. Stable across samples on the same boot.
    static func bootTime() -> Date {
        Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)
    }

    /// The challenge string for a random-string unlock.
    private static func randomChallenge(length: Int) -> String {
        let groups = [
            Array("abcdefghijkmnopqrstuvwxyz"),
            Array("ABCDEFGHJKLMNPQRSTUVWXYZ"),
            Array("23456789"),
            Array("%!?@#&*+=")
        ]
        let alphabet = groups.flatMap { $0 }
        var characters = groups.compactMap { $0.randomElement() }
        characters.append(contentsOf: (characters.count..<length).compactMap { _ in alphabet.randomElement() })
        return String(characters.shuffled())
    }
}
