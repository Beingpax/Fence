import Foundation

/// The escalation ladder for one blocked encounter.
///
/// A rule match no longer raises the shield straight away. Shift nudges first, re-checks
/// that the user is still there, and only covers the screen once the nudges have run out.
/// The point is to teach the association rather than to punish the slip: three chances to
/// close the tab yourself, then Shift closes the app for you.
///
/// Timing is driven by this type rather than by the detection sampler, so the steps land on
/// exact intervals. Presence is still authoritative: `isStillHere` runs immediately before
/// every step, and the caller resets the ladder the moment the foreground context changes.
@MainActor
final class NudgeLadder {
    /// How many nudges the user gets before the shield. The whole ladder is
    /// `stepCount * interval` seconds long.
    /// `nonisolated` because the views and the HUD copy read these while describing the
    /// ladder, and neither needs to touch its state to do that.
    nonisolated static let stepCount = 3
    nonisolated static let interval: Duration = .seconds(5)

    /// Identity of the encounter currently climbing the ladder, if any.
    private(set) var key: String?
    private(set) var step = 0
    private var task: Task<Void, Never>?

    /// Starts the ladder for `key`, or does nothing if that encounter is already climbing.
    ///
    /// - Parameters:
    ///   - onStep: shows nudge `n` of `stepCount`. Called immediately for step 1.
    ///   - isStillHere: re-checked before every later step. A `false` ends the ladder quietly.
    ///   - onExhausted: the nudges are spent — raise the shield.
    func begin(
        key: String,
        onStep: @escaping (Int) -> Void,
        isStillHere: @escaping () -> Bool,
        onExhausted: @escaping () -> Void
    ) {
        guard key != self.key else { return }

        task?.cancel()
        self.key = key
        step = 1
        onStep(1)

        task = Task { [weak self] in
            for next in 2...(Self.stepCount + 1) {
                try? await Task.sleep(for: Self.interval)
                guard !Task.isCancelled, let self, self.key == key, isStillHere() else { return }

                if next > Self.stepCount {
                    // Spent. The shield takes over, so the ladder steps aside for it.
                    self.clear()
                    onExhausted()
                    return
                } else {
                    self.step = next
                    onStep(next)
                }
            }
        }
    }

    func reset() {
        task?.cancel()
        clear()
    }

    private func clear() {
        task = nil
        key = nil
        step = 0
    }
}
