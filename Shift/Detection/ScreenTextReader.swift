import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision
import os.log

struct FrameFingerprint: Equatable, Sendable {
    let value: Int

    init?(image: CGImage) {
        // Compare reduced grayscale frames conservatively. A coarse 8x8 hash can miss
        // small changes such as a new headline on an otherwise unchanged page.
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side)
        let fingerprint: Int? = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            context.flush()
            var hasher = Hasher()
            hasher.combine(bytes: UnsafeRawBufferPointer(bytes))
            return hasher.finalize()
        }
        guard let fingerprint else { return nil }
        value = fingerprint
    }
}

struct ScreenTextSample: Sendable {
    static let limit = 2_000

    var text: String?
    var frame: FrameFingerprint?
    var unchanged = false
}

/// Both readers return bounded text. OCR can also confirm that a newly captured frame
/// matches one the caller already evaluated.
protocol ScreenTextReading: Sendable {
    func read(_ context: ScreenContext, previousFrame: FrameFingerprint?) async -> ScreenTextSample
}

/// Local, single-window screenshots. The image and Vision results stay in this call.
actor ScreenTextReader: ScreenTextReading {
    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "ScreenText")

    func read(_ context: ScreenContext, previousFrame: FrameFingerprint?) async -> ScreenTextSample {
        guard let windowID = context.windowID,
              !Task.isCancelled, PermissionsManager.isScreenRecordingGranted
        else { return ScreenTextSample() }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            guard let window = content.windows.first(where: {
                $0.windowID == windowID && $0.owningApplication?.processID == context.processID && $0.isOnScreen
            }), !window.frame.isEmpty, await Self.isForeground(context),
                  PermissionsManager.isScreenRecordingGranted
            else { return ScreenTextSample() }
            try Task.checkCancellation()

            let image = try await capture(window)
            try Task.checkCancellation()
            guard await Self.isForeground(context), PermissionsManager.isScreenRecordingGranted else {
                return ScreenTextSample()
            }

            let frame = FrameFingerprint(image: image)
            if let frame, frame == previousFrame {
                return ScreenTextSample(frame: frame, unchanged: true)
            }
            return ScreenTextSample(text: try Self.recognizeText(in: image), frame: frame)
        } catch is CancellationError {
            return ScreenTextSample()
        } catch {
            Self.log.debug("Single-window capture or text recognition failed")
            return ScreenTextSample()
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
        let text = String(lines.joined(separator: "\n").prefix(ScreenTextSample.limit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
