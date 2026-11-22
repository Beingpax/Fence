import ApplicationServices
import Foundation

/// Accessibility round trips run off the main actor and are bounded per sample.
enum WindowInspector {
    struct Snapshot: Sendable {
        let title: String?
        let url: URL?
        let windowID: CGWindowID?
    }

    static func snapshot(pid: pid_t, browser: Browser?, prepareAccessibility: Bool) async -> Snapshot {
        await Task.detached(priority: .userInitiated) {
            var window = focusedWindow(pid: pid, browser: browser, enableWebAccessibility: prepareAccessibility)
            var url = browser.flatMap { _ in window.flatMap(browserURL) }
            if prepareAccessibility, url == nil {
                try? await Task.sleep(for: .milliseconds(150))
                window = focusedWindow(pid: pid, browser: browser)
                url = window.flatMap(browserURL)
            }
            let title = window.flatMap { string($0, "AXTitle") }
            return Snapshot(title: title, url: url, windowID: frontWindowID(pid: pid, bounds: window.flatMap(bounds)))
        }.value
    }

    static func frontWindowID(pid: pid_t, bounds: CGRect? = nil) -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: dictionary),
                  !frame.isEmpty
            else { continue }

            if let bounds, !matches(frame, bounds) { continue }
            return window[kCGWindowNumber as String] as? CGWindowID
        }
        return nil
    }

    static func focusedWindow(pid: pid_t, browser: Browser?, enableWebAccessibility: Bool = false) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        if enableWebAccessibility, let browser, browser.isChromium,
           (attribute(application, "AXEnhancedUserInterface") as? Bool) != true {
            // Chromium may report an error even when this succeeds. A later read verifies it
            // and samples the tree after Chromium has had time to populate it.
            AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }

        guard let value = attribute(application, "AXFocusedWindow"),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let window = value as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.15)
        return window
    }

    static func webArea(in window: AXUIElement) -> AXUIElement? {
        var queue = [window]
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(130))
        var index = 0
        while index < queue.count, index < 72, ContinuousClock.now < deadline {
            let element = queue[index]
            index += 1
            let role = string(element, "AXRole")
            if role == "AXWebArea" { return element }
            if role == "AXToolbar" || role == "AXMenuBar" || role == "AXTabGroup" { continue }
            queue.append(contentsOf: children(of: element, limit: 24))
        }
        return nil
    }

    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ key: String) -> String? {
        guard let text = attribute(element, key) as? String, !text.isEmpty else { return nil }
        return text
    }

    static func children(of element: AXUIElement, limit: Int) -> [AXUIElement] {
        for key in ["AXVisibleChildren", "AXChildren"] {
            var count: CFIndex = 0
            guard AXUIElementGetAttributeValueCount(element, key as CFString, &count) == .success, count > 0 else {
                continue
            }
            var values: CFArray?
            if AXUIElementCopyAttributeValues(element, key as CFString, 0, min(count, limit), &values) == .success,
               let children = values as? [AXUIElement] {
                return children
            }
        }
        return []
    }

    static func pageURL(_ area: AXUIElement) -> URL? {
        webURL(attribute(area, "AXURL"))
    }

    private static func browserURL(_ window: AXUIElement) -> URL? {
        if let url = webURL(attribute(window, "AXDocument")) { return url }
        return webArea(in: window).flatMap(pageURL)
    }

    static func pageURL(_ area: AXUIElement, window: AXUIElement) -> URL? {
        pageURL(area) ?? webURL(attribute(window, "AXDocument"))
    }

    private static func webURL(_ value: CFTypeRef?) -> URL? {
        let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
        guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host() != nil else { return nil }
        return url
    }

    static func bounds(_ window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, "AXPosition"), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(window, "AXSize"), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
        else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    private static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 2 && abs(lhs.minY - rhs.minY) <= 2
            && abs(lhs.width - rhs.width) <= 2 && abs(lhs.height - rhs.height) <= 2
    }
}
