import AppKit
import SwiftUI

extension EnvironmentValues {
    /// False while the window holding this view can't be seen: closed (ordered out),
    /// minimised, on another Space or fully covered. Looping animations (the mascot's idle,
    /// onboarding's stars and dots) pause on it, so a window nobody is looking at doesn't
    /// keep redrawing 30 times a second. True by default, so surfaces that are always on
    /// screen (the nudge card, the pause) never need to set it.
    @Entry var windowIsVisible = true
}

extension View {
    /// Tracks the hosting window's occlusion and passes it down as `windowIsVisible`.
    /// Put it once at the root of a window's content.
    func tracksWindowVisibility() -> some View {
        modifier(WindowVisibilityModifier())
    }
}

private struct WindowVisibilityModifier: ViewModifier {
    @State private var isVisible = true

    func body(content: Content) -> some View {
        content
            .environment(\.windowIsVisible, isVisible)
            .background(WindowVisibilityReader(isVisible: $isVisible))
    }
}

private struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = { visible in
            if isVisible != visible { isVisible = visible }
        }
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.onChange = { visible in
            if isVisible != visible { isVisible = visible }
        }
    }

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private weak var observed: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window !== observed else { return }
            let center = NotificationCenter.default
            if let observed {
                center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: observed)
            }
            observed = window
            if let window {
                center.addObserver(
                    self, selector: #selector(occlusionChanged),
                    name: NSWindow.didChangeOcclusionStateNotification, object: window
                )
            }
            report()
        }

        @objc private func occlusionChanged(_ notification: Notification) {
            report()
        }

        private func report() {
            // No window yet counts as visible, so nothing starts out paused by accident.
            let visible = window.map { $0.occlusionState.contains(.visible) } ?? true
            // Never write SwiftUI state in the middle of a view update.
            Task { @MainActor [weak self] in self?.onChange?(visible) }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
