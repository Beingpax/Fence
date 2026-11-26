import AppKit
import ApplicationServices
import CoreGraphics
import os.log

/// Closes what the person reached for, as gently as the target allows.
///
/// When a website rule matched in a browser, that means the one tab, not the browser: the
/// pause is a nudge, not a punishment, and the other tabs are probably work. When an app
/// rule matched, browsers included, the app is asked to quit.
@MainActor
enum TabCloser {
    /// Each step of a close, so a tab that stays open can be traced:
    /// `log show --last 5m --info --predicate 'subsystem == "com.beingpax.Shift" && category == "TabCloser"'`
    private nonisolated static let log = Logger(subsystem: "com.beingpax.Shift", category: "TabCloser")

    enum CloseResult: Equatable {
        /// The tab is gone, or had already left the blocked page.
        case closed
        /// Neither the Close Tab menu item nor a keystroke could reach the browser.
        case keyboardAccessUnavailable
        /// The browser or the blocked page couldn't be found again.
        case targetUnavailable
    }

    private enum Method {
        /// The browser's own Close Tab command, pressed through Accessibility. It needs no
        /// synthetic keystroke, so it can't be dropped or land in the wrong place.
        case menuItem
        /// Command-W posted to the browser's process, for a browser whose menu can't be read.
        case keystroke
    }

    /// Brings the browser back to the front and closes the tab showing the blocked page.
    ///
    /// The page is checked against the rule (`stillBlocked`), never against the exact URL
    /// first seen: the pause usually appears before the page has loaded, and by the time
    /// someone answers, `x.com` has become `x.com/home` and Reddit has added parameters.
    /// Insisting on the same URL used to leave those tabs open.
    ///
    /// After closing, it reads the window again. Only when it can see the same page still
    /// there does it try the other method, so it never closes a second tab.
    static func closeFrontTab(
        for context: ScreenContext,
        stillBlocked: (ScreenContext) -> Bool
    ) async -> CloseResult {
        let pid = context.processID
        guard let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated, app.bundleIdentifier == context.bundleID,
              let browser = Browser(bundleID: context.bundleID) else {
            Self.log.notice("close: browser \(context.bundleID, privacy: .public) not running")
            return .targetUnavailable
        }
        let started = ContinuousClock.now
        Self.log.notice("close: \(context.appName, privacy: .public) window \(context.windowID ?? 0) host \(context.host ?? "-", privacy: .public)")
        // Shift is the active app while the pause is up, so it has to hand activation over
        // explicitly; macOS ignores a bare activate() from elsewhere. The menu command acts
        // on the key window, which is the one the pause covered.
        NSApp.yieldActivation(to: app)
        app.activate()

        // 1. The browser in front, in the same window, still on a blocked page.
        var target: ScreenContext?
        var waits: [String] = []
        var frontSince: ContinuousClock.Instant?
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(3000))
        while target == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, !app.isTerminated else { return .targetUnavailable }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                frontSince = nil
                waits.append("not-front")
                continue
            }
            // Frontmost comes a moment before the browser's window is key again, and a
            // Close Tab sent in between does nothing. Safari ignored it every time.
            let since = frontSince ?? ContinuousClock.now
            frontSince = since
            guard ContinuousClock.now - since >= .milliseconds(300) else {
                waits.append("settling")
                continue
            }
            guard let live = await frontReading(of: context, browser: browser) else {
                waits.append("no-url")
                continue
            }
            if let window = context.windowID, let liveWindow = live.windowID, window != liveWindow {
                waits.append("window \(liveWindow)")
                continue
            }
            // It already moved somewhere allowed: nothing is left to close.
            guard stillBlocked(live) else {
                Self.log.notice("close: page already allowed (\(live.host ?? "-", privacy: .public))")
                return .closed
            }
            target = live
        }
        let waited = waits.joined(separator: ",")
        guard let target else {
            Self.log.error("close: never found the blocked page; waited on \(waited, privacy: .public)")
            return .targetUnavailable
        }
        Self.log.notice("close: found \(target.host ?? "-", privacy: .public) after \(waits.count) waits [\(waited, privacy: .public)]")

        // 2. Close it, then make sure it went.
        var reachedBrowser = false
        for method in [Method.menuItem, .keystroke] {
            guard await perform(method, pid: pid) else {
                Self.log.notice("close: \(String(describing: method), privacy: .public) unavailable")
                continue
            }
            reachedBrowser = true
            let showing = await stillShowing(target, browser: browser)
            Self.log.notice("close: \(String(describing: method), privacy: .public) sent; still showing: \(String(describing: showing), privacy: .public); \((ContinuousClock.now - started).formatted(.units(allowed: [.milliseconds])), privacy: .public)")
            // Only a clear reading of the same page tries the other method. A window that
            // can't be read counts as closed: trying again on a guess could close a tab
            // that was never blocked. If it was in fact still open, the monitor sees it and
            // the pause comes back.
            if showing != true { return .closed }
        }
        Self.log.error("close: tab still open after every method")
        return reachedBrowser ? .targetUnavailable : .keyboardAccessUnavailable
    }

    /// Quits an app without bringing it forward first. If it stays open, it's most likely
    /// asking something (unsaved work, "quit with these tabs?"), so it comes forward to be
    /// answered. Otherwise whatever was behind it gets the focus, never Shift's own window.
    static func quit(pid: pid_t) async {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            activateNextApp(excluding: pid)
            return
        }
        app.terminate()
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(1500))
        while !app.isTerminated, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if app.isTerminated {
            activateNextApp(excluding: pid)
        } else {
            NSApp.yieldActivation(to: app)
            app.activate()
        }
    }

    /// Hands the focus to the frontmost window that isn't Shift's or the one just closed.
    /// The pause activated Shift; leaving it active would raise its main window when the
    /// pause goes away.
    static func activateNextApp(excluding pid: pid_t) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let owner = window[kCGWindowOwnerPID as String] as? pid_t,
                  owner != ownPID, owner != pid,
                  let app = NSRunningApplication(processIdentifier: owner),
                  !app.isTerminated, app.activationPolicy == .regular else { continue }
            NSApp.yieldActivation(to: app)
            app.activate()
            return
        }
        NSApp.deactivate()
    }

    // MARK: Reading the browser

    /// The browser's front window as it is now, or `nil` while it isn't in front or can't
    /// be read. Unlike the monitor's confirmation, a page that's still loading counts.
    private static func frontReading(of context: ScreenContext, browser: Browser) async -> ScreenContext? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processID else { return nil }
        let snapshot = await WindowInspector.snapshot(
            pid: context.processID, browser: browser, prepareAccessibility: browser.isChromium
        )
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == context.processID,
              let url = snapshot.url else {
            Self.log.debug("read: no url (title \(snapshot.title == nil ? "none" : "yes", privacy: .public), window \(snapshot.windowID ?? 0))")
            return nil
        }
        var live = context
        live.url = url
        live.windowTitle = snapshot.title
        live.windowID = snapshot.windowID
        return live
    }

    /// Whether the closed page is still on screen, read for up to two seconds. `true` only
    /// when the last reading still shows the same page in the same window; `nil` when the
    /// window couldn't be read.
    private static func stillShowing(_ target: ScreenContext, browser: Browser) async -> Bool? {
        var answer: Bool?
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(200))
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processID else {
                return false
            }
            let snapshot = await WindowInspector.snapshot(
                pid: target.processID, browser: browser, prepareAccessibility: browser.isChromium
            )
            // A window that can't be read any more was most likely the one that closed.
            guard let url = snapshot.url else { answer = nil; continue }
            let sameWindow = target.windowID == nil || snapshot.windowID == target.windowID
            if !sameWindow || url != target.url {
                Self.log.notice("verify: now showing \(url.host() ?? "-", privacy: .public) in window \(snapshot.windowID ?? 0)\(sameWindow ? "" : " (another window)", privacy: .public)")
                return false
            }
            answer = true
        }
        return answer
    }

    // MARK: Closing

    private static func perform(_ method: Method, pid: pid_t) async -> Bool {
        switch method {
        case .menuItem:
            guard PermissionsManager.canInspectApp else { return false }
            return await pressCloseTabMenuItem(pid: pid)
        case .keystroke:
            return postCommandW(pid: pid)
        }
    }

    /// Presses the menu item bound to Command-W (Close Tab, or Close Window on a window's
    /// last tab, exactly what the keystroke would do). Found by its shortcut rather than its
    /// title, so it works in every language and every browser with a standard menu bar.
    private nonisolated static func pressCloseTabMenuItem(pid: pid_t) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.5)
            guard let value = WindowInspector.attribute(application, kAXMenuBarAttribute),
                  CFGetTypeID(value) == AXUIElementGetTypeID() else {
                Self.log.notice("menu: no menu bar")
                return false
            }
            let menuBar = value as! AXUIElement
            var scanned = 0

            for barItem in axChildren(menuBar) {
                for menu in axChildren(barItem) {
                    for item in axChildren(menu) {
                        scanned += 1
                        guard let key = WindowInspector.string(item, kAXMenuItemCmdCharAttribute),
                              key.caseInsensitiveCompare("w") == .orderedSame,
                              // 0 means Command alone: not Shift-Command-W (Close Window).
                              (WindowInspector.attribute(item, kAXMenuItemCmdModifiersAttribute) as? Int) == 0,
                              (WindowInspector.attribute(item, kAXEnabledAttribute) as? Bool) != false
                        else { continue }
                        let title = WindowInspector.string(item, kAXTitleAttribute) ?? "?"
                        let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
                        Self.log.notice("menu: pressed “\(title, privacy: .public)” after \(scanned) items: \(result.rawValue)")
                        return result == .success
                    }
                }
            }
            Self.log.notice("menu: no Command-W item in \(scanned) items")
            return false
        }.value
    }

    private nonisolated static func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        WindowInspector.attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    /// Command-W, posted to the browser's process so it can only ever reach the browser.
    private static func postCommandW(pid: pid_t) -> Bool {
        guard PermissionsManager.canPostKeyboardEvents,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        let w: CGKeyCode = 0x0D
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: w, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: w, keyDown: false) else { return false }
        for event in [down, up] {
            event.flags = .maskCommand
            event.postToPid(pid)
        }
        return true
    }

    /// Used directly after confirming a URL. Never bring a background browser forward here.
    static func closeIfFrontmost(pid: pid_t) -> CloseResult {
        guard PermissionsManager.canPostKeyboardEvents else { return .keyboardAccessUnavailable }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return .targetUnavailable }
        return postCommandW(pid: pid) ? .closed : .targetUnavailable
    }
}
