import Foundation

/// Tier 2/3 (P1–P2): the on-device model. See PRD §10.
///
/// Input:  session goal + app + title + URL + OCR text (+ a downscaled frame for the VLM tier).
/// Output: structured `{ verdict, confidence, reason }`.
///
/// Runtime plan:
/// - Intent classifier (~300 MB) loaded with MLX Swift at session start, kept resident.
/// - VLM (~1 GB, 4-bit) loaded on demand, unloaded after 5 min idle.
/// - Weights live in ~/Library/Application Support/Shift/Models/<name>/<version>/,
///   are downloaded on first run, and are verified against a signed manifest.
protocol LocalIntentModel {
    var isLoaded: Bool { get }
    func load() async throws
    func unload()
    func judge(goal: String, context: ScreenContext) async -> Verdict?
}
