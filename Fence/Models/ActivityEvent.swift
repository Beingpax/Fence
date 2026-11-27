import Foundation

/// A line in the session's activity log (menu bar "Recent").
struct ActivityEvent: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let symbol: String
    let text: String

    init(_ text: String, symbol: String, date: Date = .now) {
        self.text = text
        self.symbol = symbol
        self.date = date
    }
}
