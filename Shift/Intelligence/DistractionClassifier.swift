import Foundation

/// Anything that can judge a screen against the session goal.
/// Tier 0 (rules) today; the local model tiers plug in behind the same protocol.
protocol DistractionClassifier {
    func classify(_ context: ScreenContext, session: FocusSession) -> Verdict
}

/// Runs the cheap tier first and would escalate uncertain cases to the local model (PRD §8).
struct CascadeClassifier: DistractionClassifier {
    var rules: RuleBasedClassifier
    /// nil until the model is downloaded (PRD §10). Shift is fully usable without it.
    var model: LocalIntentModel?

    func classify(_ context: ScreenContext, session: FocusSession) -> Verdict {
        let ruleVerdict = rules.classify(context, session: session)

        // Rules are decisive for clear allows and confident blocks.
        guard ruleVerdict.kind == .nudge, model != nil else { return ruleVerdict }

        // TODO(P1): run OCR + the intent model asynchronously here and replace the nudge
        // with the model's verdict when its confidence is above the threshold.
        return ruleVerdict
    }
}
