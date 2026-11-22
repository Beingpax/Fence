import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision
import os.log

/// Both readers return a fresh, bounded sample of the foreground window's text.
protocol ScreenTextReading: Sendable {
    func read(_ context: ScreenContext) async -> String?
}

extension ScreenTextReading {
    static var textLimit: Int { 2_000 }
}

/// Local, single-window screenshots. The image and Vision results stay in this call.
actor ScreenTextReader: ScreenTextReading {
    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "ScreenText")

    func read(_ context: ScreenContext) async -> String? {
        guard let windowID = context.windowID,
              !Task.isCancelled, PermissionsManager.isScreenRecordingGranted
        else { return nil }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            guard let window = content.windows.first(where: {
                $0.windowID == windowID && $0.owningApplication?.processID == context.processID && $0.isOnScreen
            }), !window.frame.isEmpty, await Self.isForeground(context),
                  PermissionsManager.isScreenRecordingGranted
            else { return nil }
            try Task.checkCancellation()

            let image = try await capture(window)
            try Task.checkCancellation()
            guard await Self.isForeground(context), PermissionsManager.isScreenRecordingGranted else {
                return nil
            }

            return try Self.recognizeText(in: image)
        } catch is CancellationError {
            return nil
        } catch {
            Self.log.debug("Single-window capture or text recognition failed")
            return nil
        }
    }

    private static func isForeground(_ context: ScreenContext) async -> Bool {
        let activePID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        return activePID == context.processID && WindowInspector.frontWindowID(pid: context.processID) == context.windowID
    }

    private func capture(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = min(1.0, 1280 / max(window.frame.width, window.frame.height))
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .nominal
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    static func recognizeText(in image: CGImage) throws -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        let lines = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        let text = String(lines.joined(separator: "\n").prefix(textLimit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
