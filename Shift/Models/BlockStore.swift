import Foundation
import Observation
import os.log

/// Owns every block, their persistence, and the rules about what the user is allowed
/// to change while a lock is engaged.
///
/// Both processes cache the block list. Each committed edit reloads the latest version
/// under a file lock so a dashboard edit cannot overwrite a lock or trigger count.
@MainActor
@Observable
final class BlockStore {
    nonisolated private static let log = Logger(subsystem: "com.beingpax.Shift", category: "BlockStore")
    private(set) var blocks: [Block] = []

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var revision: UInt64?
    @ObservationIgnored private var unlockChallenges: [Block.ID: String] = [:]
    @ObservationIgnored var onCommit: (() -> Void)?

    init(fileURL: URL? = ShiftInstallation.supportDirectory.appending(path: "blocks.json")) {
        self.fileURL = fileURL
        refreshFromDisk()
        transaction(or: ()) {
            resolveRestartLocks()
            expireFinishedRuns()
        }
    }

    convenience init(loadFromDisk: Bool) {
        self.init(fileURL: loadFromDisk ? ShiftInstallation.supportDirectory.appending(path: "blocks.json") : nil)
    }

    /// Atomic replacement gives each committed version a different inode.
    private func reload(_ url: URL) throws {
        var info = stat()
        guard stat(url.path, &info) == 0 else {
            if errno == ENOENT {
                if !blocks.isEmpty { blocks = [] }
                revision = nil
                return
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard revision != info.st_ino else { return }
        let latest = try JSONDecoder().decode([Block].self, from: Data(contentsOf: url))
        if latest != blocks { blocks = latest }
        revision = info.st_ino
    }

    func refreshFromDisk() {
        guard let fileURL else { return }
        do { try reload(fileURL) } catch {
            Self.log.error("Could not read blocks: \(error.localizedDescription, privacy: .public)")
        }
        refreshActivity()
    }

    private func transaction<T>(or failure: T, _ edit: () -> T) -> T {
        defer { refreshActivity() }
        guard let fileURL else { return edit() }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let lock = try ProcessLease(url: fileURL.appendingPathExtension("lock"), wait: true)
            let previous: [Block]
            let result: T
            do {
                defer { lock.release() }
                try reload(fileURL)
                previous = blocks
                result = edit()
                guard blocks != previous else { return result }
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(blocks)
                    try data.write(to: fileURL, options: .atomic)
                } catch {
                    blocks = previous
                    throw error
                }
                // Still under the lock, so this is the version just written. Remembering it
                // spares the next refresh from decoding what is already in memory.
                var written = stat()
                revision = stat(fileURL.path, &written) == 0 ? written.st_ino : nil
            }
            onCommit?()
            return result
        } catch {
            Self.log.error("Could not commit block change: \(error.localizedDescription, privacy: .public)")
            return failure
        }
    }

    // MARK: Queries

    /// Quit and uninstall both recheck disk after any UI confirmation delay.
    func permitsTermination(at date: Date = Date()) -> Bool {
        refreshFromDisk()
        return !blocks.contains { $0.protectsQuit(at: date) }
    }

    var activeBlocks: [Block] { blocks.filter { $0.isActive() } }

    /// Which blocks were active at the last change or engine tick. A schedule opens and
    /// closes without editing anything, so a view reading only `blocks` never hears about
    /// it: the menu bar count stayed stale until the next edit. Views read these instead;
    /// the engine keeps asking the clock directly through `activeBlocks`.
    private(set) var activeBlockIDs: Set<Block.ID> = []
    var displayedActiveBlocks: [Block] { blocks.filter { activeBlockIDs.contains($0.id) } }

    private func refreshActivity(at date: Date = Date()) {
        let ids = Set(blocks.lazy.filter { $0.isActive(at: date) }.map(\.id))
        if ids != activeBlockIDs { activeBlockIDs = ids }
    }

    var lockedBlocks: [Block] { blocks.filter { $0.isLocked() } }
    var hasLockedBlock: Bool { blocks.contains { $0.isLocked() } }

    /// The furthest-out lock deadline, which is what the watchdog needs to know.
    var lockedUntil: Date? {
        let now = Date()
        let deadlines = blocks.compactMap { block -> Date? in
            guard block.isEnabled else { return nil }
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
        transaction(or: ()) {
            guard !blocks.contains(where: { $0.id == block.id }) else { return }
            blocks.append(block)
        }
    }

    /// Edits are refused while the block is locked, so a lock can't be edited away.
    @discardableResult
    func update(_ block: Block, now: Date = Date()) -> Bool {
        transaction(or: false) {
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
            blocks[index] = updated
            return true
        }
    }

    /// While locked, the only edits allowed are ones that make the block stricter or
    /// are purely cosmetic. Anything that could weaken it is refused.
    private func isSafeEditWhileLocked(from existing: Block, to proposed: Block) -> Bool {
        guard existing.schedule == proposed.schedule else { return false }
        guard existing.lock.hasSameSettings(as: proposed.lock) else { return false }
        // Entries may be added but never removed.
        let grew = { (old: [String], new: [String]) in Set(old).isSubset(of: Set(new)) }
        guard grew(existing.list.hosts, proposed.list.hosts),
              grew(existing.list.paths, proposed.list.paths),
              grew(existing.list.apps, proposed.list.apps),
              Set(existing.list.textRules).isSubset(of: Set(proposed.list.textRules)),
              existing.list.categoryNames.isSubset(of: proposed.list.categoryNames),
              proposed.list.exceptionCategoryNames.isSubset(of: existing.list.exceptionCategoryNames),
              grew(proposed.list.websiteExceptions.map(\.entry), existing.list.websiteExceptions.map(\.entry))
        else { return false }
        return true
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        transaction(or: false) {
            guard let index = blocks.firstIndex(where: { $0.id == id }) else { return false }
            guard !blocks[index].isLocked() else { return false }
            blocks.remove(at: index)
            return true
        }
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
        transaction(or: .refusedLocked("Could not save the block.")) {
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
            return .changed
        }
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
        transaction(or: false) {
            guard let challenge = unlockChallenges[id], typed == challenge,
                  let index = blocks.firstIndex(where: { $0.id == id }),
                  blocks[index].requiresUnlockChallenge(), !blocks[index].lock.isLocked()
            else { return false }
            var block = blocks[index]
            endRun(&block)
            blocks[index] = block
            return true
        }
    }

    @discardableResult
    func startManualRun(id: UUID, minutes: Int, now: Date = Date()) -> Bool {
        transaction(or: false) {
            guard minutes > 0, let index = blocks.firstIndex(where: { $0.id == id }) else { return false }
            var block = blocks[index]
            guard block.schedule.isManual, !block.isEnabled, !block.lock.isLocked(at: now) else { return false }

            block.isEnabled = true
            block.manualRunEndsAt = now.addingTimeInterval(TimeInterval(minutes) * 60)
            engageLock(on: &block, now: now)
            blocks[index] = block
            return true
        }
    }

    // MARK: Housekeeping

    /// A `.restart` lock is released only when the machine has genuinely rebooted.
    /// The boot session ID survives app relaunches and wall-clock changes.
    private func resolveRestartLocks() {
        let currentBoot = Self.bootTime()
        let bootSessionID = Self.bootSessionID
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
            }
        }
    }

    /// Clears manual runs that finished while the app wasn't running.
    private func expireFinishedRuns() {
        let now = Date()
        for index in blocks.indices {
            var block = blocks[index]
            if retireTimedRun(&block, at: now) { blocks[index] = block }
        }
    }

    /// Called on the engine's tick to retire finished runs and locks.
    func tick(now: Date = Date()) {
        refreshActivity(at: now)
        guard blocks.contains(where: { block in
            block.schedule.isManual && block.isEnabled && !block.lock.isLocked(at: now) && (block.manualRunEndsAt ?? .distantPast) <= now
                || (!block.lock.engagedUntilRestart && block.lock.engagedUntil.map { $0 <= now } == true)
        }) else { return }
        transaction(or: ()) {
            for index in blocks.indices {
                var block = blocks[index]

                _ = retireTimedRun(&block, at: now)
                if let lockEnd = block.lock.engagedUntil, lockEnd <= now, !block.lock.engagedUntilRestart {
                    block.lock.engagedUntil = nil
                }
                if block != blocks[index] {
                    blocks[index] = block
                }
            }
        }
    }

    private func retireTimedRun(_ block: inout Block, at date: Date) -> Bool {
        guard block.schedule.isManual, block.isEnabled, !block.lock.isLocked(at: date),
              block.manualRunEndsAt.map({ $0 <= date }) ?? true
        else { return false }
        endRun(&block)
        return true
    }

    func recordTrigger(id: UUID, now: Date = Date()) {
        transaction(or: ()) {
            guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
            blocks[index].stats.timesTriggered += 1
            blocks[index].stats.lastTriggered = now
        }
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
