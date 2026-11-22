import CoreGraphics
import Foundation
import os.log
import ScreenCaptureKit
import Vision

/// Tier 1b: on-screen text, via ScreenCaptureKit and Vision.
///
/// This is the expensive tier, so it is gated three ways. It only runs when a block
/// actually needs it, it only runs on the frontmost window, and it skips entirely when
/// the picture hasn't meaningfully changed since last time. Nothing is ever written to
/// disk: a frame exists for the length of one recognition pass and is then gone.
protocol ScreenTextReading: Sendable {
    func readFrontmostWindowText(pid: pid_t) async -> String?
}

/// An actor, so the change-detection hash is isolated and the capture never runs on the
/// main thread. Capture and recognition are both genuinely slow; keeping them off the
/// main actor is what stops the UI from stuttering while a block is being evaluated.
actor ScreenTextReader: ScreenTextReading {
    private static let log = Logger(subsystem: "com.beingpax.Shift", category: "ScreenText")

    /// Longest side of the captured frame. Vision reads small text fine at this size and
    /// it keeps the recognition pass cheap.
    private let maxDimension = 1280
    /// Characters handed onward. Keeps us well inside any future model's context budget.
    private let characterCap = 2000
    /// Hamming distance below which two frames count as "the same screen".
    private let sameFrameThreshold = 4

    private var lastHash: UInt64?
    private var lastPID: pid_t?

    func readFrontmostWindowText(pid: pid_t) async -> String? {
        guard PermissionsManager.isScreenRecordingGranted else { return nil }

        do {
            guard let window = try await frontmostWindow(for: pid) else { return nil }
            guard let image = try await capture(window) else { return nil }

            // Change gate. A screen that hasn't changed can't have changed its meaning.
            let hash = Self.perceptualHash(of: image)
            if let hash, lastPID == pid, let previous = lastHash,
               Self.hammingDistance(hash, previous) <= sameFrameThreshold {
                return nil
            }
            lastHash = hash
            lastPID = pid

            return try await recognizeText(in: image)
        } catch {
            Self.log.error("Screen text read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Forgets the change gate, so the next read is guaranteed to do real work.
    func invalidateChangeGate() {
        lastHash = nil
        lastPID = nil
    }

    // MARK: Capture

    private func frontmostWindow(for pid: pid_t) async throws -> SCWindow? {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        return content.windows
            .filter { $0.owningApplication?.processID == pid && $0.isOnScreen }
            .filter { $0.frame.width > 120 && $0.frame.height > 120 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private func capture(_ window: SCWindow) async throws -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)

        let configuration = SCStreamConfiguration()
        let scale = min(
            1.0,
            Double(maxDimension) / max(window.frame.width, window.frame.height)
        )
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        configuration.captureResolution = .nominal

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    // MARK: Recognition

    private func recognizeText(in image: CGImage) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let joined = lines.joined(separator: "\n")
                continuation.resume(returning: joined.isEmpty ? nil : String(joined.prefix(self.characterCap)))
            }
            // Fast is the right trade here: we're keyword matching, not transcribing.
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: Change detection

    /// Classic 8x8 average hash. Cheap, and good enough to answer "is this the same screen".
    nonisolated static func perceptualHash(of image: CGImage) -> UInt64? {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        let total = pixels.reduce(0) { $0 + Int($1) }
        let average = UInt8(total / pixels.count)

        var hash: UInt64 = 0
        for (index, pixel) in pixels.enumerated() where pixel > average {
            hash |= (1 << UInt64(index))
        }
        return hash
    }

    nonisolated static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}

/// Used when the screen reader is switched off, so the cascade has something to call.
struct DisabledScreenTextReader: ScreenTextReading {
    func readFrontmostWindowText(pid: pid_t) async -> String? { nil }
}
