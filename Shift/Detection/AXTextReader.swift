import ApplicationServices
import Foundation

struct AXTextReader: ScreenTextReading {
    func read(_ context: ScreenContext, previousFrame: FrameFingerprint?) async -> ScreenTextSample {
        let task = Task.detached(priority: .utility) { Self.readText(context) }
        let text = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        return ScreenTextSample(text: text)
    }

    private static func readText(_ context: ScreenContext) -> String? {
        let browser = Browser(bundleID: context.bundleID)
        guard !Task.isCancelled,
              let windowID = context.windowID,
              let window = WindowInspector.focusedWindow(pid: context.processID, browser: browser),
              WindowInspector.frontWindowID(pid: context.processID, bounds: WindowInspector.bounds(window)) == windowID
        else { return nil }

        let root: AXUIElement
        if browser != nil {
            guard let area = WindowInspector.webArea(in: window),
                  context.url == nil || WindowInspector.pageURL(in: window, area: area) == context.url
            else { return nil }
            root = area
        } else {
            root = window
        }

        let skippedRoles: Set<String> = [
            "AXMenu", "AXMenuBar", "AXToolbar", "AXTextField", "AXTextArea", "AXComboBox",
        ]
        let textRoles: Set<String> = ["AXStaticText", "AXHeading"]
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(200))
        var characters = 0
        var lines: [String] = []
        var seen: Set<String> = []
        var queue = [root]
        var index = 0

        while index < queue.count, index < 160, characters < ScreenTextSample.limit,
              !Task.isCancelled, ContinuousClock.now < deadline {
            let element = queue[index]
            index += 1
            let role = WindowInspector.string(element, "AXRole") ?? ""
            if skippedRoles.contains(role) || WindowInspector.string(element, "AXSubrole") == "AXSecureTextField" {
                continue
            }

            if textRoles.contains(role),
               let raw = WindowInspector.string(element, "AXValue") ?? WindowInspector.string(element, "AXTitle") {
                let bounded = String(raw.prefix(ScreenTextSample.limit - characters))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !bounded.isEmpty, seen.insert(bounded).inserted {
                    lines.append(bounded)
                    characters += bounded.count + 1
                }
            }

            queue.append(contentsOf: WindowInspector.children(of: element, limit: 24))
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
