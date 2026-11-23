import ApplicationServices
import Foundation

/// Accessibility round trips run off the main actor and are bounded per sample.
enum WindowInspector {
    struct Snapshot: Sendable {
        let title: String?
        let url: URL?
        let windowID: CGWindowID?

        static let empty = Snapshot(title: nil, url: nil, windowID: nil)
    }

    enum QuitDialog: Equatable {
        case present, absent, unavailable
    }

    private struct AddressBarReading {
        let url: URL
        let isHostOnly: Bool
    }

    private static let addressFieldIDs: Set<String> = [
        "addressbar", "omnibox", "urlbar", "urlbar-input", "urlfieldinput", "web_browser_address_and_search_field",
    ]
    private static let addressFieldLabels: Set<String> = [
        "address and search bar", "address and search field", "address bar", "search or enter website name",
        "address field", "enter search or web address", "smart search field",
    ]
    private static let vivaldiInterfaceURL = "chrome-extension://mpognobbkildjkofajifpdfhcoklimli/window.html"
    private static let webAreaRoles: Set<String> = ["AXWebArea", "AXDocument"]

    static func snapshot(
        pid: pid_t, browser: Browser?, prepareAccessibility: Bool, verifyURL: Bool = false
    ) async -> Snapshot {
        let worker = Task.detached(priority: .userInitiated) {
            var snapshot = autoreleasepool {
                readSnapshot(pid: pid, browser: browser, prepareAccessibility: prepareAccessibility, verifyURL: verifyURL)
            }
            if prepareAccessibility, !verifyURL, snapshot.url == nil, browser != nil, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                snapshot = autoreleasepool {
                    readSnapshot(pid: pid, browser: browser, prepareAccessibility: false, verifyURL: false)
                }
            }
            return snapshot
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func readSnapshot(pid: pid_t, browser: Browser?, prepareAccessibility: Bool, verifyURL: Bool) -> Snapshot {
        guard !Task.isCancelled else { return .empty }
        let window = focusedWindow(pid: pid, browser: browser, enableWebAccessibility: prepareAccessibility)
        var url: URL?
        if let browser, let window, !Task.isCancelled {
            if verifyURL {
                if let address = verifiedPageURL(in: window, browser: browser),
                   let latestWindow = focusedWindow(pid: pid, browser: browser), CFEqual(window, latestWindow) {
                    url = address
                }
            } else {
                url = pageURL(in: window, browser: browser)
            }
        }
        // The Chromium preparation path retries once before publishing a sample.
        guard !Task.isCancelled, !prepareAccessibility || verifyURL || url != nil else { return .empty }
        let title = window.flatMap { string($0, "AXTitle") }
        let windowID = title == nil && url == nil ? nil : frontWindowID(pid: pid, bounds: window.flatMap(bounds))
        return Snapshot(title: title, url: url, windowID: windowID)
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

    /// A window's frame as the window server reports it: screen coordinates with the
    /// origin at the top left of the primary display. No Accessibility round trip.
    static func frame(of windowID: CGWindowID) -> CGRect? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]])?.first,
              let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: dictionary), !frame.isEmpty
        else { return nil }
        return frame
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
        guard !Task.isCancelled, AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        if enableWebAccessibility, browser == .dia {
            AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
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

    static func webArea(in window: AXUIElement, browser: Browser) -> AXUIElement? {
        guard let root = browserRoot(in: window, browser: browser) else { return nil }
        return webAreas(in: root, vivaldi: browser == .vivaldi, limit: 1).first
    }

    private static func browserRoot(in window: AXUIElement, browser: Browser) -> AXUIElement? {
        guard browser == .vivaldi else { return window }
        return webAreas(in: window, vivaldi: false, limit: 4).first {
            url(attribute($0, "AXURL"))?.absoluteString == vivaldiInterfaceURL
        }
    }

    private static func webAreas(in root: AXUIElement, vivaldi: Bool, limit: Int) -> [AXUIElement] {
        var queue = vivaldi ? children(of: root, limit: 40).map { ($0, false) } : [(root, true)]
        var found: [AXUIElement] = []
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(vivaldi ? 200 : 130))
        let nodeLimit = vivaldi ? 240 : 96
        var index = 0
        while index < queue.count, index < nodeLimit, ContinuousClock.now < deadline, !Task.isCancelled {
            let (element, activePage) = queue[index]
            index += 1
            guard let role = string(element, "AXRole") else { continue }
            if role == "AXWebArea" || (role == "AXDocument" && pageAddress(element) != nil) {
                if activePage, !found.contains(where: { CFEqual($0, element) }) {
                    found.append(element)
                    if found.count == limit { break }
                }
                continue
            }
            if ["AXToolbar", "AXMenuBar", "AXMenu", "AXSheet", "AXDialog"].contains(role) { continue }

            var belongsToActivePage = activePage
            if vivaldi, role == "AXGroup" {
                if string(element, "AXDOMIdentifier") == "panels-container" { continue }
                let classes = attribute(element, "AXDOMClassList") as? [String] ?? []
                if classes.contains("webpageview") {
                    guard classes.contains("active") else { continue }
                    belongsToActivePage = true
                }
            }
            let childLimit = min(nodeLimit - queue.count, vivaldi ? 40 : 24)
            if childLimit > 0 {
                queue.append(contentsOf: children(of: element, limit: childLimit).map { ($0, belongsToActivePage) })
            }
        }
        return found
    }

    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        guard !Task.isCancelled else { return nil }
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
            guard !Task.isCancelled else { return [] }
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

    static func pageURL(in window: AXUIElement, browser: Browser, area: AXUIElement? = nil) -> URL? {
        if browser != .vivaldi, let primary = windowURLs(window).first {
            return isWebURL(primary) ? primary : nil
        }
        guard let root = browserRoot(in: window, browser: browser) else { return nil }
        let areas = area.map { [$0] } ?? webAreas(in: root, vivaldi: browser == .vivaldi, limit: 2)
        if areas.count > 1 { return nil }
        if let page = areas.first.flatMap(pageAddress) {
            return isWebURL(page) ? page : nil
        }
        return addressBarReading(in: root)?.url
    }

    private static func verifiedPageURL(in window: AXUIElement, browser: Browser) -> URL? {
        guard let root = browserRoot(in: window, browser: browser) else { return nil }
        let areas = webAreas(in: root, vivaldi: browser == .vivaldi, limit: 3)
        // A close command targets a single tab. A split view is ambiguous.
        guard areas.count <= 1 else { return nil }
        let areaURLs = areas.compactMap(pageAddress)
        let primary = (browser == .vivaldi ? [] : windowURLs(window)) + areaURLs
        let addressBar = addressBarReading(in: root)
        guard let first = primary.first else { return addressBar?.url }
        guard let address = WebsiteAddress(url: first),
              primary.dropFirst().allSatisfy({ $0.scheme == first.scheme && samePage($0, first) }) else { return nil }

        if let addressBar {
            guard let displayed = WebsiteAddress(url: addressBar.url),
                  samePage(addressBar.url, first) || (browser == .webKit && addressBar.isHostOnly && displayed.host == address.host)
            else { return nil }
        }
        return first
    }

    private static func samePage(_ lhs: URL, _ rhs: URL) -> Bool {
        // A browser may omit the scheme or a trailing slash in its address field.
        let leftPath = lhs.path(percentEncoded: true)
        let rightPath = rhs.path(percentEncoded: true)
        return lhs.host()?.lowercased() == rhs.host()?.lowercased() && lhs.port == rhs.port
            && (leftPath.isEmpty ? "/" : leftPath) == (rightPath.isEmpty ? "/" : rightPath)
            && lhs.query() == rhs.query() && lhs.fragment() == rhs.fragment()
    }

    private static func windowURLs(_ window: AXUIElement) -> [URL] {
        ["AXDocument", "AXURL"].compactMap { url(attribute(window, $0)) }.filter { $0.scheme != nil }
    }

    private static func pageAddress(_ area: AXUIElement) -> URL? {
        guard let candidate = url(attribute(area, "AXURL")), candidate.scheme != nil else { return nil }
        return candidate
    }

    private static func addressBarReading(in window: AXUIElement) -> AddressBarReading? {
        // Search browser chrome only. Never interpret page content as a location.
        let excludedRoles = webAreaRoles.union(["AXMenu", "AXMenuBar", "AXSheet", "AXDialog"])
        var queue = children(of: window, limit: 32).map { (element: $0, inToolbar: false) }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(130))
        var index = 0
        while index < queue.count, index < 96, ContinuousClock.now < deadline, !Task.isCancelled {
            let (element, inToolbar) = queue[index]
            index += 1
            guard let role = string(element, "AXRole"), !excludedRoles.contains(role) else { continue }
            if (role == "AXTextField" || role == "AXComboBox" || role == "AXSearchField"),
               isAddressField(element, inToolbar: inToolbar),
               attribute(element, "AXFocused") as? Bool == false,
               let value = string(element, "AXValue"), let reading = addressBarValue(value) {
                return reading
            }
            let childIsInToolbar = inToolbar || role == "AXToolbar"
            let childLimit = min(96 - queue.count, 24)
            if childLimit > 0 {
                queue.append(contentsOf: children(of: element, limit: childLimit).map { ($0, childIsInToolbar) })
            }
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

    private static func addressBarValue(_ value: String) -> AddressBarReading? {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        if let url = URL(string: value), isWebURL(url) {
            return AddressBarReading(url: url, isHostOnly: false)
        }
        // Browsers can omit the scheme. Require a recognizable host before assuming HTTPS.
        guard !value.contains("://"), let url = URL(string: "https://\(value)"), let host = url.host(),
              url.user() == nil, url.password() == nil,
              host.contains(".") || host.contains(":") || host.lowercased() == "localhost" else { return nil }
        return AddressBarReading(url: url, isHostOnly: !value.contains { "/?#".contains($0) })
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
