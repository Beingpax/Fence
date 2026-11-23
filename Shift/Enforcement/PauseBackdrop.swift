import AppKit
import Observation
import SwiftUI

/// Clock bands shared by the lighting variants of every landscape.
enum DayPeriod: String, CaseIterable {
    /// 05:00–09:00.
    case sunrise
    /// 09:00–13:00.
    case morning
    /// 13:00–17:00.
    case afternoon
    /// 17:00–20:30.
    case sunset
    /// 20:30–05:00.
    case night

    init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        switch minutes {
        case 300..<540: self = .sunrise
        case 540..<780: self = .morning
        case 780..<1020: self = .afternoon
        case 1020..<1230: self = .sunset
        default: self = .night
        }
    }
}

struct PauseWallpaperSelection: Equatable {
    enum Landscape: String, CaseIterable {
        case acaciaPlain = "acacia-plain"
        case redDune = "red-dune"
        case snowyRidge = "snowy-ridge"
        case greenHills = "green-hills"
    }

    let landscape: Landscape
    let period: DayPeriod

    init(date: Date, timeZone: TimeZone = .autoupdatingCurrent) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        period = DayPeriod(date: date, calendar: calendar)

        // Count between local midnights so the rotation steps once on short and long days.
        let today = calendar.startOfDay(for: date)
        let referenceDay = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1)) ?? today
        let days = calendar.dateComponents([.day], from: referenceDay, to: today).day ?? 0
        let landscapes = Landscape.allCases
        let index = (days % landscapes.count + landscapes.count) % landscapes.count
        landscape = landscapes[index]
    }

    var resourceName: String { "PauseWallpaper-\(landscape.rawValue)-\(period.rawValue)" }

    /// Keep the white type readable while preserving detail in the darkest frames.
    var scrim: Double {
        switch (landscape, period) {
        case (_, .sunrise): 0.54
        case (_, .morning), (_, .afternoon): 0.56
        case (_, .sunset), (.snowyRidge, .night): 0.42
        case (_, .night): 0.16
        }
    }
}

/// One active image shared by all pause windows. The bundled JPEG stays out of AppKit's named image cache.
@MainActor
@Observable
final class PauseWallpaper {
    private(set) var selection: PauseWallpaperSelection
    private(set) var image: NSImage?

    init() {
        let selection = PauseWallpaperSelection(date: .now)
        self.selection = selection
        image = Self.load(selection)
    }

    func followClock() async {
        while !Task.isCancelled {
            let now = Date.now
            let next = PauseWallpaperSelection(date: now)
            if next != selection {
                selection = next
                image = Self.load(next)
            }

            // Wake on the clock minute while the pause is open, including across midnight.
            let nextMinute = Calendar.autoupdatingCurrent.dateInterval(of: .minute, for: now)?.end
            let delay = max(0.1, nextMinute?.timeIntervalSinceNow ?? 60)
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
        }
    }

    private static func load(_ selection: PauseWallpaperSelection) -> NSImage? {
        Bundle.main.url(forResource: selection.resourceName, withExtension: "jpg")
            .flatMap { NSImage(contentsOf: $0) }
    }
}

/// The landscape behind the pause, chosen by the time of day.
///
/// It arrives with a slow pull-back from a slight zoom and then keeps drifting, very
/// slowly, for as long as the pause is up. A still photo at this size reads as a poster;
/// one that breathes reads as a place. Under Reduce Motion it simply holds still.
struct PauseBackdrop: View {
    let wallpaper: PauseWallpaper

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    @State private var drifting = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.06, green: 0.07, blue: 0.09)

                if let image = wallpaper.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(reduceMotion ? 1 : (arrived ? (drifting ? 1.06 : 1.0) : 1.14))
                        .offset(x: reduceMotion ? 0 : (drifting ? -geometry.size.width * 0.012 : 0))
                        .clipped()
                }

                Color.black.opacity(wallpaper.selection.scrim)

                // Give the text a consistent base as it moves between pause phases.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.18), location: 0),
                        .init(color: .black.opacity(0.12), location: 0.32),
                        .init(color: .black.opacity(0.12), location: 0.72),
                        .init(color: .black.opacity(0.24), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )

                // Vignette: holds the eye in the middle and keeps the corners quiet.
                RadialGradient(
                    colors: [.clear, .black.opacity(0.28)],
                    center: .center, startRadius: 380, endRadius: 1200
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6)) { arrived = true }
            withAnimation(.easeInOut(duration: 40).repeatForever(autoreverses: true).delay(1.6)) {
                drifting = true
            }
        }
    }
}
