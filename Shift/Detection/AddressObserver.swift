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
    private var registration: Task<ObserverBox?, Never>?

    /// Starts listening to `pid`, replacing whatever was observed before.
    func observe(pid: pid_t) {
        guard pid != self.pid else { return }
        stop()
        self.pid = pid
        registerIfNeeded()
    }

    private func registerIfNeeded() {
        guard registration == nil, let pid else { return }
        let expected = generation
        let context = ObserverContext(owner: self)

        // Registering messages the other process, so it runs off the main actor.
        let worker = Task.detached(priority: .utility) {
            autoreleasepool { Self.makeObserver(pid: pid, context: context) }
        }
        registration = worker
        Task { [weak self] in
            let box = await worker.value
            guard let self else { return }
            self.registration = nil
            guard self.generation == expected else {
                self.registerIfNeeded()
                return
            }
            guard let box else { return }
            self.observer = box
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(box.observer), .defaultMode)
        }
    }

    func stop() {
        generation &+= 1
        registration?.cancel()
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

    private nonisolated static func makeObserver(pid: pid_t, context: ObserverContext) -> ObserverBox? {
        guard !Task.isCancelled else { return nil }
        var created: AXObserver?
        guard AXObserverCreate(pid, addressObserverCallback, &created) == .success, let created else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        let refcon = Unmanaged.passUnretained(context).toOpaque()
        let notifications = [
            kAXFocusedUIElementChangedNotification,
            kAXTitleChangedNotification,
            kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification,
            "AXLoadComplete",
        ]
        var registered = 0
        for name in notifications {
            guard !Task.isCancelled else { return nil }
            if AXObserverAddNotification(created, app, name as CFString, refcon) == .success {
                registered += 1
            }
        }
        return registered > 0 ? ObserverBox(observer: created, context: context) : nil
    }
}

@MainActor
private final class ObserverContext {
    weak var owner: AddressObserver?

    init(owner: AddressObserver) { self.owner = owner }
}

/// `AXObserver` is a CF object that is only touched on the main run loop once created.
private final class ObserverBox: @unchecked Sendable {
    let observer: AXObserver
    private let context: ObserverContext

    init(observer: AXObserver, context: ObserverContext) {
        self.observer = observer
        self.context = context
    }

    deinit {
        CFRunLoopSourceInvalidate(AXObserverGetRunLoopSource(observer))
    }
}

/// Runs on the main run loop, which is where the observer's source was added.
private let addressObserverCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let context = Unmanaged<ObserverContext>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { context.owner?.fire() }
}
