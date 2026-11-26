import Foundation

var failures = 0
@MainActor
func check(_ label: String, _ condition: Bool) {
    if condition { print("  ok   \(label)") } else { print("  FAIL \(label)"); failures += 1 }
}

func date(_ weekday: Int, _ hour: Int, _ minute: Int) -> Date {
    // Build a date in the current week with the given weekday/time.
    var components = DateComponents()
    components.year = 2026
    components.month = 11
    // 2026-11-22 is a Sunday (weekday 1), so day = 21 + weekday.
    components.day = 21 + weekday
    components.hour = hour
    components.minute = minute
    return Calendar.current.date(from: components)!
}

if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--record-triggers" {
    let store = BlockStore(fileURL: URL(fileURLWithPath: CommandLine.arguments[2]))
    guard let id = UUID(uuidString: CommandLine.arguments[3]) else { exit(2) }
    for _ in 0..<12 { store.recordTrigger(id: id) }
    exit(0)
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--fixture-agent" {
    let directory = URL(fileURLWithPath: CommandLine.arguments[2])
    let lease = try ProcessLease(url: directory.appending(path: "monitor.lock"))
    let store = BlockStore(fileURL: directory.appending(path: "blocks.json"))
    let rules = BlockEvaluator(blocks: store.activeBlocks, driftKeywords: [])
    let game = ScreenContext(bundleID: "org.example.game", appName: "Game", processID: 1)
    let page = ScreenContext(bundleID: "com.apple.Safari", appName: "Safari", processID: 2, url: URL(string: "https://example.com/feed"))
    guard rules.ruleVerdict(for: game)?.kind == .block, rules.ruleVerdict(for: page)?.kind == .block else { exit(2) }
    FileHandle.standardOutput.write(Data([1]))
    withExtendedLifetime(lease) { while true { pause() } }
}

// A disposable dashboard process commits its block and then waits for termination.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--fixture-dashboard" {
    let directory = URL(fileURLWithPath: CommandLine.arguments[2])
    let dashboard = BlockStore(fileURL: directory.appending(path: "blocks.json"))
    var fixture = Block(name: "No lock")
    fixture.isEnabled = true
    fixture.list.apps = ["org.example.game"]
    fixture.list.paths = ["example.com/feed"]
    dashboard.add(fixture)
    let lease = try ProcessLease(url: directory.appending(path: "dashboard.lock"))
    FileHandle.standardOutput.write(Data([1]))
    withExtendedLifetime(lease) { while true { pause() } }
}

print("ScheduleWindow: weekday 9 to 17")
var work = ScheduleWindow()
work.days = Weekday.weekdays
work.start = TimeOfDay(hour: 9, minute: 0)
work.end = TimeOfDay(hour: 17, minute: 0)
check("Monday 10:00 is inside", work.contains(date(2, 10, 0)))
check("Monday 08:59 is outside", !work.contains(date(2, 8, 59)))
check("Monday 17:00 is outside (end exclusive)", !work.contains(date(2, 17, 0)))
check("Sunday 10:00 is outside (not a weekday)", !work.contains(date(1, 10, 0)))

print("ScheduleWindow: overnight 22:00 to 06:00")
var night = ScheduleWindow()
night.days = [.monday]
night.start = TimeOfDay(hour: 22, minute: 0)
night.end = TimeOfDay(hour: 6, minute: 0)
check("Monday 23:00 is inside", night.contains(date(2, 23, 0)))
check("Tuesday 02:00 is inside (spills past midnight)", night.contains(date(3, 2, 0)))
check("Tuesday 07:00 is outside", !night.contains(date(3, 7, 0)))
check("Monday 21:00 is outside", !night.contains(date(2, 21, 0)))

print("BlockLock: untilTime rolls to tomorrow when already past")
var lock = BlockLock()
lock.method = .untilTime
lock.untilTime = TimeOfDay(hour: 17, minute: 0)
let morning = date(2, 9, 0)
let evening = date(2, 19, 0)
let fromMorning = lock.engagementDeadline(from: morning)!
let fromEvening = lock.engagementDeadline(from: evening)!
check("from 09:00 lands today at 17:00", Calendar.current.isDate(fromMorning, equalTo: date(2, 17, 0), toGranularity: .minute))
check("from 19:00 lands tomorrow at 17:00", Calendar.current.isDate(fromEvening, equalTo: date(3, 17, 0), toGranularity: .minute))

print("BlockLock: duration")
var dur = BlockLock()
dur.method = .duration
dur.duration = 3600
check("deadline is one hour out", Int(dur.engagementDeadline(from: morning)!.timeIntervalSince(morning)) == 3600)

print("BlockLock: isLocked")
var engaged = BlockLock()
engaged.engagedUntil = morning.addingTimeInterval(600)
check("locked before deadline", engaged.isLocked(at: morning))
check("unlocked after deadline", !engaged.isLocked(at: morning.addingTimeInterval(700)))
var restart = BlockLock()
restart.engagedUntilRestart = true
check("restart lock always locked", restart.isLocked(at: Date.distantFuture))

print("Block.isActive")
var block = Block(name: "Test")
block.schedule = .always
block.isEnabled = false
check("disabled and unlocked is inactive", !block.isActive(at: morning))
block.isEnabled = true
check("enabled always-on is active", block.isActive(at: morning))
block.schedule = .scheduled([work])
check("scheduled inside window is active", block.isActive(at: date(2, 10, 0)))
check("scheduled outside window is inactive", !block.isActive(at: date(2, 20, 0)))
block.schedule = .manual(minutes: 25)
block.manualRunEndsAt = morning.addingTimeInterval(600)
check("manual run active before it ends", block.isActive(at: morning))
check("manual run inactive after it ends", !block.isActive(at: morning.addingTimeInterval(700)))

print("App rules outrank website rules")
var arcAndX = Block(name: "Distractions")
arcAndX.list.apps = ["company.thebrowser.Browser"]
arcAndX.list.hosts = ["x.com"]
var onlyX = Block(name: "Sites")
onlyX.list.hosts = ["x.com"]
var onlyArc = Block(name: "Browsers")
onlyArc.list.apps = ["company.thebrowser.Browser"]
let arcOnX = ScreenContext(bundleID: "company.thebrowser.Browser", appName: "Arc", processID: 3, url: URL(string: "https://x.com/home"))
let safariOnX = ScreenContext(bundleID: "com.apple.Safari", appName: "Safari", processID: 4, url: URL(string: "https://x.com/home"))
check("same block: Arc on x.com quits Arc",
      BlockEvaluator(blocks: [arcAndX], driftKeywords: []).ruleVerdict(for: arcOnX)?.ruleTarget == .app("company.thebrowser.browser"))
check("separate blocks: the app rule wins even when listed second",
      BlockEvaluator(blocks: [onlyX, onlyArc], driftKeywords: []).ruleVerdict(for: arcOnX)?.ruleTarget == .app("company.thebrowser.browser"))
check("an unblocked browser on x.com closes the tab",
      BlockEvaluator(blocks: [arcAndX], driftKeywords: []).ruleVerdict(for: safariOnX)?.ruleTarget == .website("x.com"))

print("Quit protection")
var policy = Block(name: "Focus")
policy.isEnabled = true
check("Always blocks protect Quit without a lock", policy.protectsQuit(at: morning))
policy.schedule = .scheduled([work])
check("scheduled block protects inside its window", policy.protectsQuit(at: morning))
check("waiting schedule permits Quit", !policy.protectsQuit(at: evening))
policy.lock.engagedUntil = evening.addingTimeInterval(60)
check("an existing lock still protects outside its window", policy.protectsQuit(at: evening))
policy.lock.engagedUntil = nil
policy.schedule = .manual(minutes: 20)
policy.manualRunEndsAt = morning.addingTimeInterval(60)
check("manual run protects until its exact deadline", policy.protectsQuit(at: morning) && !policy.protectsQuit(at: morning.addingTimeInterval(60)))
policy.isEnabled = false
check("disabled blocks permit Quit", !policy.protectsQuit(at: morning))

print("Force Quit and independent rule evaluation")
@MainActor
func checkEnforcement() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let removalRules = directory.appending(path: "removal-rules.json")
    let removalWindow = BlockStore(fileURL: removalRules)
    let otherWindow = BlockStore(fileURL: removalRules)
    check("idle app permits uninstall preparation", removalWindow.permitsTermination(at: morning))
    var timedBlock = Block(name: "Unlocked timer")
    timedBlock.schedule = .manual(minutes: 25)
    timedBlock.isEnabled = true
    timedBlock.manualRunEndsAt = morning.addingTimeInterval(60)
    otherWindow.add(timedBlock)
    check("uninstall confirmation sees a newly started unlocked block", !removalWindow.permitsTermination(at: morning))
    check("uninstall preparation becomes available at expiry", removalWindow.permitsTermination(at: morning.addingTimeInterval(60)))

    func startFixture(_ mode: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [mode, directory.path]
        let ready = Pipe()
        process.standardOutput = ready
        try process.run()
        var fd = pollfd(fd: ready.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&fd, 1, 5000) > 0, ready.fileHandleForReading.readData(ofLength: 1) == Data([1]) else {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw POSIXError(.EIO)
        }
        return process
    }

    let dashboard = try startFixture("--fixture-dashboard")
    defer {
        if dashboard.isRunning { kill(dashboard.processIdentifier, SIGKILL); dashboard.waitUntilExit() }
    }
    let file = directory.appending(path: "blocks.json")
    let worker = BlockStore(fileURL: file)
    let settings = BlockStore(fileURL: file)
    guard var draft = settings.blocks.first else { check("fixture saved", false); return }
    let game = ScreenContext(bundleID: "org.example.game", appName: "Game", processID: 1)
    let page = ScreenContext(bundleID: "com.apple.Safari", appName: "Safari", processID: 2, url: URL(string: "https://example.com/feed"))
    func blocks(_ context: ScreenContext) -> Bool {
        BlockEvaluator(blocks: worker.activeBlocks, driftKeywords: []).ruleVerdict(for: context)?.kind == .block
    }
    check("agent sees app and browser-path rules", blocks(game) && blocks(page))
    let presence = directory.appending(path: "dashboard.lock")
    let competingLease = try? ProcessLease(url: presence)
    check("a live owner excludes a second claimant", competingLease == nil)

    kill(dashboard.processIdentifier, SIGKILL)
    dashboard.waitUntilExit()
    check("macOS killed the fixture dashboard", dashboard.terminationReason == .uncaughtSignal && dashboard.terminationStatus == SIGKILL)
    check("agent still evaluates both rules after Force Quit", blocks(game) && blocks(page))
    let replacement = try ProcessLease(url: presence)
    replacement.release()
    check("the terminated process released its lease", true)

    // Simulate the two launches in isolation; launchd itself is outside this test.
    let firstAgent = try startFixture("--fixture-agent")
    kill(firstAgent.processIdentifier, SIGKILL)
    firstAgent.waitUntilExit()
    check("fixture agent received Force Quit", firstAgent.terminationReason == .uncaughtSignal && firstAgent.terminationStatus == SIGKILL)
    let restartedAgent = try startFixture("--fixture-agent")
    check("replacement agent acquired the monitor and loaded both rules with the dashboard closed", restartedAgent.isRunning)
    kill(restartedAgent.processIdentifier, SIGKILL)
    restartedAgent.waitUntilExit()

    worker.recordTrigger(id: draft.id)
    draft.name = "Renamed in dashboard"
    check("dashboard saves an edit based on a stale snapshot", settings.update(draft))
    worker.refreshFromDisk()
    check("both processes' edits survive", worker.blocks.first?.stats.timesTriggered == 1 && worker.blocks.first?.name == draft.name)
    let writer = Process()
    writer.executableURL = dashboard.executableURL
    writer.arguments = ["--record-triggers", file.path, draft.id.uuidString]
    try writer.run()
    for _ in 0..<12 { worker.recordTrigger(id: draft.id) }
    writer.waitUntilExit()
    worker.refreshFromDisk()
    check("simultaneous commits from both processes preserve every trigger",
          writer.terminationStatus == 0 && worker.blocks.first?.stats.timesTriggered == 25)
    _ = settings.setEnabled(false, for: draft.id)
    worker.refreshFromDisk()
    check("explicitly stopping the unlocked block releases both targets", !blocks(game) && !blocks(page))
}
do { try checkEnforcement() } catch { check("isolated process checks: \(error)", false) }

print("")
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
