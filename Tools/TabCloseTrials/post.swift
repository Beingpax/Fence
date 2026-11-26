import Foundation
DistributedNotificationCenter.default().postNotificationName(Notification.Name(CommandLine.arguments[1]), object: nil, userInfo: nil, deliverImmediately: true)
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
