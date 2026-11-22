import Foundation

var failures = 0
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
block.breaks.isEnabled = true
block.breaks.currentBreakEndsAt = morning.addingTimeInterval(300)
check("on a break is inactive", !block.isActive(at: morning))
block.breaks.currentBreakEndsAt = nil
block.schedule = .scheduled([work])
check("scheduled inside window is active", block.isActive(at: date(2, 10, 0)))
check("scheduled outside window is inactive", !block.isActive(at: date(2, 20, 0)))
block.schedule = .manual(minutes: 25)
block.manualRunEndsAt = morning.addingTimeInterval(600)
check("manual run active before it ends", block.isActive(at: morning))
check("manual run inactive after it ends", !block.isActive(at: morning.addingTimeInterval(700)))

print("")
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
