import AppKit

/// The three sounds Fence makes, each with one job.
///
/// - **pause**: a soft, low singing-bowl chime as the pause covers the page. An
///   invitation to breathe, never an alarm, because shame and alarm make people fight
///   the tool rather than listen to it.
/// - **reward**: a bright rising glass bell the moment someone turns back on their own.
///   This is the most important of the three: behaviour that's rewarded straight away is
///   behaviour that repeats, and turning back is the habit Fence is trying to build.
/// - **deep** (`shield.m4a`): a calm, deep chord in place of the chime from the third
///   reach in an hour. Firmer, but a reset, not a louder warning.
///
/// Trimmed, faded and loudness-matched with ffmpeg. They live in `Resources/Sounds`. Settings → Nudges → Sounds turns them off.
@MainActor
enum NudgeSound {
    private static var cache: [String: NSSound] = [:]

    static func playPause() { play("pause") }
    static func playReward() { play("reward") }
    static func playDeep() { play("shield") }

    private static func play(_ name: String) {
        guard let sound = sound(named: name) else { return }
        // Started over rather than stacked when the same sound comes round again quickly.
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    private static func sound(named name: String) -> NSSound? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
              let sound = NSSound(contentsOf: url, byReference: true)
        else { return nil }
        sound.volume = 0.8
        cache[name] = sound
        return sound
    }
}
