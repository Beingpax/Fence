import AppKit
import ImageIO
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

/// One active image shared by all pause windows. The bundled JPEG stays out of AppKit's
/// named image cache, so it is freed with the pause.
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

    /// Decodes the photo once, no larger than the biggest display needs (about 15 MB at full
    /// size; less on a smaller display).
    ///
    /// The photos are generated and were upscaled to 4K, so they carry no real detail past
    /// 2560 px: shrinking to 2560 and back scored 49–51 dB. They ship as 2560×1440 JPEG XL
    /// (`cjxl -d 1.0 -e 9`, SSIMULACRA2 ≥ 85.8), about 380 KB each. At equal perceptual
    /// quality JPEG XL came out about half the size of JPEG and 15–20% under AVIF, and
    /// ImageIO decodes it in about 30 ms cold, faster than JPEG (≈60 ms) and far faster
    /// than AVIF or HEIC (110–150 ms). This decode sits between the reach and the pause.
    private static func load(_ selection: PauseWallpaperSelection) -> NSImage? {
        guard let url = Bundle.main.url(forResource: selection.resourceName, withExtension: "jxl"),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }

        var options: [CFString: Any] = [
            // Never the small preview the file may embed.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           let limit = neededLongSide(width: width, height: height) {
            options[kCGImageSourceThumbnailMaxPixelSize] = limit
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// The photo fills each screen and arrives slightly zoomed in, so the scale that matters
    /// is the larger of width and height, on the most demanding display. Nil keeps full size.
    private static func neededLongSide(width: Int, height: Int) -> Int? {
        guard width > 0, height > 0 else { return nil }
        let scale = NSScreen.screens.map { screen in
            let pixels = screen.convertRectToBacking(screen.frame).size
            return max(pixels.width / CGFloat(width), pixels.height / CGFloat(height))
        }.max() ?? 1
        let needed = scale * PauseBackdrop.arrivalZoom
        guard needed > 0, needed < 1 else { return nil }
        return Int((CGFloat(max(width, height)) * needed).rounded(.up))
    }
}

/// The landscape behind the pause, chosen by the time of day.
///
/// It arrives with a slow pull-back from a slight zoom and then keeps drifting, very
/// slowly, for as long as the pause is up. A still photo at this size reads as a poster;
/// one that breathes reads as a place. Under Reduce Motion it simply holds still.
struct PauseBackdrop: View {
    let wallpaper: PauseWallpaper

    /// How far in the photo starts before it pulls back. The wallpaper is decoded for this.
    static let arrivalZoom: CGFloat = 1.14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.09)

            if let image = wallpaper.image {
                // The pull-back and the drift run in Core Animation (`DriftingPhoto`). As a
                // SwiftUI `repeatForever` animation the drift updated and laid out the whole
                // pause, panel and all, every frame for as long as it was up: about half of
                // the pause's steady 14% CPU in Instruments (26 Nov 2026).
                DriftingPhoto(image: image, moves: !reduceMotion)
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
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The photo, filling its frame: it arrives zoomed in by `PauseBackdrop.arrivalZoom` and
/// pulls back over 1.6 s, then drifts (6% closer and 1.2% of the width to the left) and
/// back every 40 s, for as long as it's on screen. Held still when `moves` is false.
private struct DriftingPhoto: NSViewRepresentable {
    let image: NSImage
    let moves: Bool

    func makeNSView(context: Context) -> DriftingPhotoView {
        let view = DriftingPhotoView()
        view.show(image, moves: moves)
        return view
    }

    func updateNSView(_ view: DriftingPhotoView, context: Context) {
        view.show(image, moves: moves)
    }
}

final class DriftingPhotoView: NSView {
    /// Carries the sideways drift; `photo` inside it carries the zoom, as SwiftUI's
    /// `.scaleEffect(...).offset(x:)` did.
    private let drift = CALayer()
    private let photo = CALayer()
    private var shown: NSImage?
    private var moves = false
    private var started = false

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        photo.contentsGravity = .resizeAspectFill
        drift.addSublayer(photo)
        layer?.addSublayer(drift)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ image: NSImage, moves: Bool) {
        if image !== shown {
            shown = image
            photo.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil) ?? image
        }
        self.moves = moves
        startIfReady()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        drift.frame = bounds
        photo.frame = bounds
        CATransaction.commit()
        startIfReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        photo.contentsScale = window?.backingScaleFactor ?? 2
        startIfReady()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        photo.contentsScale = window?.backingScaleFactor ?? 2
    }

    /// Once, when the view first has a size in a window: the same curves and timings the
    /// SwiftUI version used (`.easeOut(duration: 1.6)`, then `.easeInOut(duration: 40)`
    /// repeating forever with autoreverse after a 1.6 s delay).
    private func startIfReady() {
        guard moves, !started, window != nil, bounds.width > 0 else { return }
        started = true
        let now = CACurrentMediaTime()

        let arrival = CABasicAnimation(keyPath: "transform.scale")
        arrival.fromValue = PauseBackdrop.arrivalZoom
        arrival.toValue = 1.0
        arrival.duration = 1.6
        arrival.timingFunction = CAMediaTimingFunction(name: .easeOut)
        photo.add(arrival, forKey: "arrival")

        let zoom = CABasicAnimation(keyPath: "transform.scale")
        zoom.fromValue = 1.0
        zoom.toValue = 1.06
        let sideways = CABasicAnimation(keyPath: "transform.translation.x")
        sideways.fromValue = 0
        sideways.toValue = -bounds.width * 0.012
        for (animation, layer, key) in [(zoom, photo, "zoom"), (sideways, drift, "drift")] {
            animation.beginTime = now + 1.6
            animation.duration = 40
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: key)
        }
    }
}
