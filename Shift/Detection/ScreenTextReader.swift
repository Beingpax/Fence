import Foundation

/// Tier 1 (P1): on-screen text via ScreenCaptureKit + Vision OCR. See PRD §8.
///
/// Implementation plan:
/// 1. `SCShareableContent` → find the frontmost window's `SCWindow`.
/// 2. `SCScreenshotManager.captureImage` with a single-window `SCContentFilter`, scaled down to ~1280 px.
/// 3. Perceptual hash vs. the previous frame; skip OCR if the screen barely changed.
/// 4. `VNRecognizeTextRequest` (`.fast`, on the Neural Engine) → joined text, capped at ~2k chars.
/// 5. Keep frames in memory only. Never write them to disk (PRD §11).
///
/// Needs the Screen Recording permission. When it's missing, return nil and let Tier 0 decide.
protocol ScreenTextReading {
    func readFrontmostWindowText() async -> String?
}

struct ScreenTextReaderStub: ScreenTextReading {
    func readFrontmostWindowText() async -> String? { nil }
}
