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
    /// How many nudges the user gets before the shield.
    /// `nonisolated` because the views and the HUD copy read these while describing the
    /// ladder, and neither needs to touch its state to do that.
    nonisolated static let stepCount = 3
    /// How long a rung stays on screen.
    nonisolated static let visible: Duration = .seconds(5)
    /// The gap between rungs, with nothing on screen at all.
    ///
    /// The pause is the point. Three nudges arriving back to back read as one long
    /// complaint; appearing, leaving, and coming back reads as someone checking on you,
    /// and it gives a quiet moment in which to actually close the tab.
    nonisolated static let rest: Duration = .seconds(5)

    /// Identity of the encounter currently climbing the ladder, if any.
    private(set) var key: String?
    private(set) var step = 0
    private var task: Task<Void, Never>?

    /// Starts the ladder for `key`, or does nothing if that encounter is already climbing.
    ///
    /// Each rung shows for `visible`, then goes away for `rest` before the next one. The
    /// last rung also goes away before the shield, so the screen is quiet for a beat
    /// rather than cutting straight from a nudge to a wall.
    ///
    /// - Parameters:
    ///   - onStep: shows nudge `n` of `stepCount`. Called immediately for step 1.
    ///   - onRest: takes the nudge off screen, between rungs and before the shield.
    ///   - isStillHere: re-checked at every transition. A `false` ends the ladder quietly.
    ///   - onExhausted: recheck the foreground and raise the shield if still appropriate.
    func begin(
        key: String,
        onStep: @escaping (Int) -> Void,
        onRest: @escaping () -> Void,
        isStillHere: @escaping () -> Bool,
        onExhausted: @escaping () async -> Void
    ) {
        guard key != self.key else { return }

        task?.cancel()
        self.key = key
        step = 1
        onStep(1)

        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if !Task.isCancelled, self.key == key {
                    self.clear()
                    onRest()
                }
            }
            for rung in 1...Self.stepCount {
                try? await Task.sleep(for: Self.visible)
                guard !Task.isCancelled, self.key == key, isStillHere() else { return }

                // Off screen between rungs, and before the shield.
                onRest()
                guard rung < Self.stepCount else { break }

                try? await Task.sleep(for: Self.rest)
                guard !Task.isCancelled, self.key == key, isStillHere() else { return }
                self.step = rung + 1
                onStep(rung + 1)
            }

            // Let the last nudge actually leave the screen before the shield lands, so
            // it reads as a decision rather than a jump cut.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, self.key == key, isStillHere() else { return }
            await onExhausted()
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
