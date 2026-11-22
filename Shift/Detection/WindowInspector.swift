import ApplicationServices
import Foundation

/// Accessibility round trips run off the main actor and are bounded per sample.
enum WindowInspector {
    struct Snapshot: Sendable {
        let title: String?
        let url: URL?
        let windowID: CGWindowID?
    }

    enum QuitDialog: Equatable {
        case present, absent, unavailable
    }

    private static let addressFieldIDs: Set<String> = [
        "addressbar", "omnibox", "urlbar", "urlbar-input", "urlfieldinput", "web_browser_address_and_search_field",
    ]
    private static let addressFieldLabels: Set<String> = [
        "address and search bar", "address and search field", "address bar", "search or enter website name",
    ]

    static func snapshot(pid: pid_t, browser: Browser?, prepareAccessibility: Bool) async -> Snapshot {
        await Task.detached(priority: .userInitiated) {
            var window = focusedWindow(pid: pid, browser: browser, enableWebAccessibility: prepareAccessibility)
            var url = browser.flatMap { _ in window.flatMap { pageURL(in: $0) } }
            if browser != nil, prepareAccessibility, url == nil {
                try? await Task.sleep(for: .milliseconds(150))
                window = focusedWindow(pid: pid, browser: browser)
                url = window.flatMap { pageURL(in: $0) }
            }
            let title = window.flatMap { string($0, "AXTitle") }
            return Snapshot(title: title, url: url, windowID: frontWindowID(pid: pid, bounds: window.flatMap(bounds)))
        }.value
    }

    static func quitDialog(pid: pid_t) async -> QuitDialog {
        await Task.detached(priority: .userInitiated) {
            guard let window = focusedWindow(pid: pid, browser: nil),
                  let role = string(window, "AXRole") else { return QuitDialog.unavailable }
            let subrole = string(window, "AXSubrole")
            if role == "AXSheet" || role == "AXDialog" || subrole == "AXDialog" || subrole == "AXSystemDialog"
                || attribute(window, "AXModal") as? Bool == true {
                return .present
            }
            var sheets: CFIndex = 0
            if AXUIElementGetAttributeValueCount(window, "AXSheets" as CFString, &sheets) == .success {
                return sheets > 0 ? .present : .absent
            }
            var count: CFIndex = 0
            guard AXUIElementGetAttributeValueCount(window, "AXChildren" as CFString, &count) == .success
            else { return .unavailable }
            guard count > 0 else { return .absent }
            var values: CFArray?
            guard AXUIElementCopyAttributeValues(window, "AXChildren" as CFString, 0, min(count, 24), &values) == .success,
                  let children = values as? [AXUIElement] else { return .unavailable }
            let roles = children.compactMap { string($0, "AXRole") }
            if roles.contains("AXSheet") { return .present }
            return roles.count == count ? .absent : .unavailable
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

static func pageURL(in window: AXUIElement, area: AXUIElement? = nil) -> URL? {
        let document = url(attribute(window, "AXDocument"))
        if let document, isWebURL(document) { return document }
        if let area = area ?? webArea(in: window), let page = url(attribute(area, "AXURL")), page.scheme != nil {
            return isWebURL(page) ? page : nil
        }
        guard document?.scheme == nil else { return nil }
        return addressBarURL(in: window)
    }

    private static func addressBarURL(in window: AXUIElement) -> URL? {
        // Search browser chrome only. Never interpret page content as a location.
        let excludedRoles: Set<String> = ["AXWebArea", "AXMenu", "AXMenuBar", "AXSheet", "AXDialog"]
        var queue = [(element: window, inToolbar: false)]
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(130))
        var index = 0
        while index < queue.count, index < 60, ContinuousClock.now < deadline {
            let (element, inToolbar) = queue[index]
            index += 1
            guard let role = string(element, "AXRole"), !excludedRoles.contains(role) else { continue }
            if (role == "AXTextField" || role == "AXComboBox"),
               isAddressField(element, inToolbar: inToolbar),
               attribute(element, "AXFocused") as? Bool == false,
               let value = string(element, "AXValue"), let url = addressBarValue(value) {
                return url
            }
            let childIsInToolbar = inToolbar || role == "AXToolbar"
            queue.append(contentsOf: children(of: element, limit: 24).map { ($0, childIsInToolbar) })
        }
        return nil
    }

    private static func isAddressField(_ element: AXUIElement, inToolbar: Bool) -> Bool {
        if ["AXIdentifier", "AXDOMIdentifier"].contains(where: {
            string(element, $0).map { addressFieldIDs.contains($0.lowercased()) } ?? false
        }) { return true }
        return inToolbar && ["AXDescription", "AXPlaceholderValue", "AXTitle"].contains(where: {
            string(element, $0).map { addressFieldLabels.contains($0.lowercased()) } ?? false
        })
    }

    private static func addressBarValue(_ value: String) -> URL? {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        if let url = URL(string: value), isWebURL(url) { return url }
        // Browsers can omit the scheme. Require a recognizable host before assuming HTTPS.
        guard let url = URL(string: "https://\(value)"), let host = url.host(),
              url.user() == nil, url.password() == nil,
              host.contains(".") || host.contains(":") || host.lowercased() == "localhost" else { return nil }
        return url
    }

    private static func url(_ value: CFTypeRef?) -> URL? {
        (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
    }

    private static func isWebURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return (scheme == "http" || scheme == "https") && url.host()?.isEmpty == false
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
