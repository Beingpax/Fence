import ApplicationServices
import Foundation

/// Hears the front app change what it's showing, the moment it happens.
///
/// The sampler polls every 1.5 s, which is too slow for the pause: by the time a poll lands,
/// the feed has loaded and the first scroll has already paid out. This observer subscribes
/// to the app's own Accessibility notifications instead, so pressing Return in the address
/// bar wakes Shift within about a tenth of a second:
///
/// - **Focused element changed.** Return moves focus from the address field to the page.
///   This is the earliest reliable signal in Safari and Chromium alike.
/// - **Title changed**, as a new page commits.
/// - **Load complete**, which WebKit posts on the web area.
/// - **Focused or main window changed**, for switching windows inside the same app.
///
/// It only *asks* for a sample; the sampler still reads the address and decides. Polling
/// stays on as the backstop for apps that post nothing.
///
/// Deliberately not observed: value changes. They fire on every keystroke in every text
/// field, which would turn typing in a document into a stream of samples for nothing.
@MainActor
final class AddressObserver {
    var onChange: (() -> Void)?

    private var observer: ObserverBox?
    private(set) var pid: pid_t?
    private var generation = 0
    private var pending: Task<Void, Never>?

    /// Starts listening to `pid`, replacing whatever was observed before.
    func observe(pid: pid_t) {
        guard pid != self.pid else { return }
        stop()
        self.pid = pid
        generation &+= 1
        let expected = generation
        let refcon = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())

        // Registering messages the other process, so it runs off the main actor.
        Task.detached(priority: .utility) {
            let box = Self.makeObserver(pid: pid, refcon: refcon)
            await MainActor.run { [weak self] in
                guard let self, let box, self.generation == expected else { return }
                self.observer = box
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(box.observer), .defaultMode)
            }
        }
    }

    func stop() {
        generation &+= 1
        pending?.cancel()
        pending = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer.observer), .defaultMode)
        }
        observer = nil
        pid = nil
    }

    /// Coalesces a burst of notifications (a page load posts several) into one sample.
    fileprivate func fire() {
        guard pending == nil else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            self.onChange?()
        }
    }

    private nonisolated static func makeObserver(pid: pid_t, refcon: UInt) -> ObserverBox? {
        var created: AXObserver?
        guard AXObserverCreate(pid, addressObserverCallback, &created) == .success, let created else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        let context = UnsafeMutableRawPointer(bitPattern: refcon)
        let notifications = [
            kAXFocusedUIElementChangedNotification,
            kAXTitleChangedNotification,
            kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification,
            "AXLoadComplete",
        ]
        var registered = 0
        for name in notifications where AXObserverAddNotification(created, app, name as CFString, context) == .success {
            registered += 1
        }
        return registered > 0 ? ObserverBox(observer: created) : nil
    }
}

/// `AXObserver` is a CF object that is only touched on the main run loop once created.
private struct ObserverBox: @unchecked Sendable {
    let observer: AXObserver
}

/// Runs on the main run loop, which is where the observer's source was added.
private let addressObserverCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let target = Unmanaged<AddressObserver>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { target.fire() }
}
