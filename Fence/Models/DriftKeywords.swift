import Foundation

/// Words that only ever nudge. Global rather than per block, because drift isn't about
/// any one rule the user wrote.
enum DriftKeywords {
    static let `default` = ["Shorts", "Reels", "For You", "Trending", "Explore"]
}
