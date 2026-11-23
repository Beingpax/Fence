import SwiftUI

/// The part of the day a pause lands in, and the landscape that goes with it.
///
/// The pause is the one surface in Shift that fills a display, so it gets real photographs
/// rather than a gradient: green land under the sky as it actually looks outside right now.
/// Matching the light outside makes the pause feel like a window rather than a wall, and
/// a calm landscape is the opposite of the feed it's standing in front of.
///
/// All five are under the Unsplash License. See `CREDITS.md`.
enum DayPeriod: CaseIterable {
    /// 05:00–09:00. Mist and low gold light over a meadow.
    case sunrise
    /// 09:00–13:00. Bright green hills under a clear blue sky.
    case morning
    /// 13:00–17:00. Savanna grass and acacias in full afternoon light.
    case afternoon
    /// 17:00–20:30. A green field under a burning sky.
    case sunset
    /// 20:30–05:00. The Milky Way over green hills.
    case night

    init(date: Date = Date(), calendar: Calendar = .current) {
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

    var imageName: String {
        switch self {
        case .sunrise: "BackdropSunrise"
        case .morning: "BackdropMorning"
        case .afternoon: "BackdropAfternoon"
        case .sunset: "BackdropSunset"
        case .night: "BackdropNight"
        }
    }

    /// How much to darken the photo so white type stays readable. Tuned by measuring each
    /// photo's brightness where the title sits: after this, none is above about 0.42 of
    /// full white there, which white type with its soft shadow clears comfortably.
    var scrim: Double {
        switch self {
        case .sunrise: 0.46
        case .morning: 0.46
        case .afternoon: 0.50
        case .sunset: 0.30
        case .night: 0.22
        }
    }

    /// The light inside the breathing orb, taken from the photo's own sky so the orb looks
    /// lit by the same sun rather than pasted on top: gold and rose at dawn, sky and leaf at
    /// midday, amber at the savanna, ember at sunset, indigo under the stars.
    var glow: [Color] {
        switch self {
        case .sunrise: [Color(red: 1.0, green: 0.78, blue: 0.52), Color(red: 0.98, green: 0.60, blue: 0.58), Color(red: 1.0, green: 0.90, blue: 0.62)]
        case .morning: [Color(red: 0.58, green: 0.82, blue: 1.0), Color(red: 0.60, green: 0.92, blue: 0.76), Color(red: 0.86, green: 0.94, blue: 1.0)]
        case .afternoon: [Color(red: 1.0, green: 0.80, blue: 0.48), Color(red: 0.76, green: 0.86, blue: 0.56), Color(red: 1.0, green: 0.92, blue: 0.72)]
        case .sunset: [Color(red: 1.0, green: 0.56, blue: 0.44), Color(red: 0.92, green: 0.48, blue: 0.70), Color(red: 1.0, green: 0.78, blue: 0.44)]
        case .night: [Color(red: 0.48, green: 0.54, blue: 1.0), Color(red: 0.72, green: 0.56, blue: 1.0), Color(red: 0.44, green: 0.82, blue: 0.92)]
        }
    }

    /// The fallback colour behind the photo while it decodes.
    var ground: Color {
        switch self {
        case .sunrise: Color(red: 0.42, green: 0.38, blue: 0.24)
        case .morning: Color(red: 0.24, green: 0.42, blue: 0.30)
        case .afternoon: Color(red: 0.45, green: 0.40, blue: 0.24)
        case .sunset: Color(red: 0.30, green: 0.18, blue: 0.20)
        case .night: Color(red: 0.05, green: 0.07, blue: 0.15)
        }
    }
}

/// The landscape behind the pause, chosen by the time of day.
///
/// It arrives with a slow pull-back from a slight zoom and then keeps drifting, very
/// slowly, for as long as the pause is up. A still photo at this size reads as a poster;
/// one that breathes reads as a place. Under Reduce Motion it simply holds still.
struct PauseBackdrop: View {
    var period = DayPeriod()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    @State private var drifting = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                period.ground

                Image(period.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(reduceMotion ? 1 : (arrived ? (drifting ? 1.06 : 1.0) : 1.14))
                    .offset(x: reduceMotion ? 0 : (drifting ? -geometry.size.width * 0.012 : 0))
                    .clipped()

                // Even dimming first, so bright daylight can carry white type at all.
                Color.black.opacity(period.scrim)

                // Then a little extra at the top and bottom, where the eye rests least.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.22), location: 0.0),
                        .init(color: .clear, location: 0.35),
                        .init(color: .clear, location: 0.70),
                        .init(color: .black.opacity(0.25), location: 1.0),
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
