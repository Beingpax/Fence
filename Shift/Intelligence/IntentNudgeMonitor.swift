import Foundation

/// Requires two fresh readings of the same foreground context before suggesting a nudge.
@MainActor
final class IntentNudgeMonitor {
    private struct PendingNudge {
        let source: Verdict.Source
        let recheckAt: SuspendingClock.Instant
    }

    private let classifier = IntentClassifier()
    private let confirmationDelay: Duration = .seconds(15)
    private var task: Task<Void, Never>?
    private var inFlight: IntentRequest?
    private var evaluated: IntentRequest?
    private var pending: PendingNudge?

    func reset() {
        task?.cancel()
        evaluated = nil
        pending = nil
    }

    func observe(
        _ request: IntentRequest,
        canDeliver: @escaping (Verdict.Source?) -> Bool,
        onVerdict: @escaping (Verdict?) -> Void
    ) {
        if evaluated == request {
            guard let pending, SuspendingClock.now >= pending.recheckAt else { return }
        } else {
            pending = nil
            evaluated = nil
        }

        if inFlight != request { task?.cancel() }
        guard task == nil else { return }
        inFlight = request

        task = Task { [weak self, classifier] in
            let reading = await classifier.classify(request)
            guard let self else { return }
            self.task = nil
            self.inFlight = nil
            guard !Task.isCancelled, canDeliver(reading?.source) else { return }
            onVerdict(self.record(reading, request: request))
        }
    }

    private func record(_ reading: IntentReading?, request: IntentRequest) -> Verdict? {
        let previous = pending
        pending = nil
        evaluated = request

        guard let reading else { return nil }
        switch reading.activity {
        case .work:
            return Verdict(kind: .allow, reason: "Visible activity looks like work", source: reading.source)
        case .unclear:
            return nil
        case .unrelatedLeisure:
            if previous?.source == reading.source {
                return Verdict(kind: .nudge, reason: "Still working on your focus goal?", source: reading.source)
            }
            if previous == nil {
                pending = PendingNudge(source: reading.source, recheckAt: .now.advanced(by: confirmationDelay))
            }
            return nil
        }
    }
}
