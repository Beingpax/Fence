import Foundation

/// Only act after N consistent readings, so a single stray frame never triggers a block.
struct Hysteresis {
    let requiredHits: Int
    private var signature: String?
    private var hits = 0

    init(requiredHits: Int) {
        self.requiredHits = requiredHits
    }

    /// Returns true when `signature` has been seen `requiredHits` times in a row.
    mutating func register(_ signature: String) -> Bool {
        if signature == self.signature {
            hits += 1
        } else {
            self.signature = signature
            hits = 1
        }
        guard hits >= requiredHits else { return false }
        reset()
        return true
    }

    mutating func reset() {
        signature = nil
        hits = 0
    }
}
