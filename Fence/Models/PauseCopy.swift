import Foundation

/// Every line Fence says at the pause, on the heads-up card and when someone turns back.
///
/// Lots of them, on purpose. The same sentence every time stops being read by the third
/// time, and a pause that's skimmed has no effect. Lines are dealt from a shuffled deck
/// (`CopyDeck`), so none repeats until all the others in its set have been shown.
///
/// Rewritten in full on 26 Nov 2026 at the user's request: every line has to make sense in
/// the exact moment it appears. The rules, for anyone adding lines:
/// - **A friend, not a warden.** Warm, a little wry, always on the person's side. The urge
///   is "the pull" or "the habit", never the person. No shame.
/// - **True to the moment.** Pause lines come during one breath, before the question. Praise
///   comes after naming a feeling, writing why and closing. Heads-up praise may follow a
///   switch to another app, so it says "moved on", never "closed". Nothing assumes work.
/// - **Nothing made up.** No numbers ("ten minutes saved"), no promises ("it gets easier
///   from here"), no scores or streaks: a tally makes it a machine keeping score.
/// - **Say what they did** rather than grading them; a little warmth is fine.
/// - **Fits the card.** Praise titles about 30 characters at most, the line under them two
///   lines of the nudge card (about 70 characters). Pause titles under about six words.
/// - No exclamation marks.
enum PauseCopy {
    typealias Line = (title: String, subtitle: String)
    /// A turning-back line and the mascot's mood for it, chosen with the words.
    typealias Reward = (title: String, subtitle: String, mood: MascotMood)

    // MARK: The pause

    /// The first reach within an hour.
    static let firstReach: [Line] = [
        ("Take a breath.", "In slowly, out slower."),
        ("Hey. Just a moment.", "Let your shoulders drop for one breath."),
        ("Pause here.", "One breath, then a quick word on what pulled you."),
        ("Before you go in.", "Take one slow breath with me."),
        ("Let’s slow down.", "The next click can wait a few seconds."),
        ("A moment first.", "Unclench your jaw and breathe out."),
        ("Breathe with me.", "In through your nose, out through your mouth."),
        ("One breath.", "That’s all this asks of you."),
        ("Hands off for a second.", "Let them rest while you breathe."),
        ("Look up for a moment.", "Rest your eyes on something far away."),
        ("A small pause.", "Notice what you were reaching for."),
        ("Easy does it.", "Drop your shoulders and let the breath out."),
        ("Here’s a breath.", "Take it slowly. Nothing is going anywhere."),
        ("Just a beat.", "Feel your feet on the floor."),
        ("Hey, it’s okay.", "This is a pause, not a wall."),
        ("Catch your breath.", "Then we’ll see what pulled you here."),
        ("Notice the pull.", "No need to fight it. Just breathe."),
        ("A moment to land.", "Let your breathing slow down on its own."),
        ("Five seconds.", "One breath in, one long breath out."),
        ("Slow down a little.", "Sit back and let your breath settle."),
        ("Let the moment pass.", "Pulls rise and fall. Breathe while this one does."),
        ("Quick pause.", "Soften your face and breathe out."),
        ("Stay with me a second.", "One calm breath before anything else."),
        ("Here, for a breath.", "Let your eyes rest away from the screen."),
    ]

    /// The second reach within an hour. The pause is the same every time; only the words
    /// change, warmer as the same pull comes back.
    static let secondReach: [Line] = [
        ("Back again.", "Same pull, same breath. Let it pass."),
        ("Hey, again.", "No problem. One more slow breath."),
        ("Hello again.", "Nothing wrong with coming back. Breathe."),
        ("You’re back.", "That’s okay. Breathe with me."),
        ("The pull came back.", "That’s what pulls do. Let this breath out slowly."),
        ("Here we are again.", "A slow breath is a good place to start."),
        ("Again? That’s okay.", "Habits knock more than once."),
        ("Another moment.", "Notice what brought you back here."),
        ("Same spot, new moment.", "Breathe out a little longer this time."),
        ("No judgment.", "Just one more slow breath."),
        ("It’s okay to be back.", "Rest your hands and breathe."),
        ("Let’s pause again.", "Lean back and let your shoulders drop."),
        ("Back for another look?", "Take a breath first. Then decide."),
        ("One more breath.", "Let your eyes rest somewhere away from the screen."),
        ("Easy now.", "Feel your feet, then breathe out."),
        ("Hey, you.", "Same pause as before. You know the way."),
        ("A familiar pull.", "Breathe first. You’ll name it in a moment."),
        ("Again, gently.", "Nothing to prove here. Just breathe."),
        ("Still curious?", "Breathe first. The feed isn’t going anywhere."),
        ("The habit’s knocking.", "You don’t have to answer. Breathe."),
    ]

    /// The third reach and beyond within an hour: a hard stretch, met gently.
    static let laterReach: [Line] = [
        ("Still pulling.", "Look away for a moment and breathe."),
        ("This one keeps coming back.", "That’s how habits feel. Breathe through it."),
        ("A sticky one today.", "Be easy on yourself. One slow breath."),
        ("Take your time.", "Nothing here is in a hurry."),
        ("Let’s stay here a moment.", "Let your breathing settle into its own rhythm."),
        ("Slow all the way down.", "Rest your hands in your lap and breathe."),
        ("It’s a strong pull.", "Strong pulls pass too. Breathe with this one."),
        ("Still here with you.", "The next step can wait while you breathe."),
        ("Maybe something’s up.", "A pull this persistent usually means something."),
        ("Step back for a breath.", "Find something far away and rest your eyes on it."),
        ("Again, and that’s okay.", "Tough hours happen. Breathe out slowly."),
        ("Let’s reset.", "Drop your shoulders. Unclench your jaw."),
        ("You keep ending up here.", "Worth asking why. Breathe first."),
        ("Breathe this one out.", "Long and slow, like letting air out of a balloon."),
        ("A heavy pull.", "You don’t have to fight it. Just breathe."),
        ("Quiet for a moment.", "Close your eyes for this breath if you like."),
        ("Give it a breath.", "Urges rise, peak and fade. Let this one fade."),
        ("Hey, take care.", "This might be a sign you need a real rest."),
        ("Stay here a moment.", "Naming the pull loosens its grip."),
        ("One more pause.", "Same breath, same choice. You’ve got this."),
    ]

    @MainActor
    static func pause(visit: Int) -> Line {
        let (deck, lines): (String, [Line]) = switch visit {
        case ...1: ("pause.first", firstReach)
        case 2: ("pause.second", secondReach)
        default: ("pause.later", laterReach)
        }
        return CopyDeck.draw(lines, deck: deck)
    }

    // MARK: The heads-up

    /// The heads-up card's headline the first time in an hour. The first `%@` is the site
    /// or app, the second (where there is one) the block's name.
    static let warningFirst = [
        "%@ is on your %@ list.",
        "%@ is blocked right now.",
        "%@? Not right now.",
        "Heads-up: %@ is blocked.",
        "That’s %@. It’s blocked.",
    ]
    /// The second time within the hour.
    static let warningSecond = [
        "Back on %@?",
        "%@ again?",
        "Hey, %@ again.",
        "Here again, on %@?",
        "Back to %@ so soon?",
    ]
    /// The third time and beyond.
    static let warningLater = [
        "%@, again.",
        "Still reaching for %@.",
        "%@ keeps calling.",
        "Back to %@ again.",
        "%@ one more time.",
    ]

    /// The heads-up card: its headline, the line under it and the mascot's mood. Annoyed
    /// the first two times in an hour, sad from the third: disappointed rather than angrier.
    /// `variant` picks a fixed headline (for the gallery); otherwise one is dealt.
    @MainActor
    static func warning(name: String, blockName: String, count: Int, closesTab: Bool, variant: Int? = nil)
        -> (headline: String, detail: String, mood: MascotMood) {
        // Short, and true: at the deadline Fence steps in with the pause.
        let detail = closesTab ? "Close the tab, or I’ll step in." : "Quit the app, or I’ll step in."
        let (deck, lines, mood): (String, [String], MascotMood) = switch count {
        case ...1: ("warning.first", warningFirst, .annoyed)
        case 2: ("warning.second", warningSecond, .annoyed)
        default: ("warning.later", warningLater, .sad)
        }
        let template = variant.map { lines[$0 % lines.count] } ?? CopyDeck.draw(lines, deck: deck)
        let headline = template.components(separatedBy: "%@").enumerated().map { index, part in
            index == 0 ? part : (index == 1 ? name : blockName) + part
        }.joined()
        return (headline, detail, mood)
    }

    // MARK: Turning back

    /// After the pause: named, written, closed. Shown on a first reach, alternating with
    /// the lines for the feeling they named.
    static let turnedBack: [Reward] = [
        ("Nicely done.", "You noticed, you chose, you closed. That’s the habit.", .happy),
        ("Back to it.", "The feed stays closed. Your time stays yours.", .happy),
        ("Good call.", "That tab won’t miss you.", .happy),
        ("There you go.", "Breathe, name it, close it. That’s the whole method.", .happy),
        ("Way to go.", "Your attention is yours again.", .cheer),
        ("That counts.", "Every close teaches your brain a new default.", .proud),
        ("Not today, feed.", "You’ve got better places to be.", .cheer),
        ("High five.", "Turning back is worth celebrating.", .cheer),
        ("Quiet win.", "Nobody saw it, and it still counts.", .happy),
        ("Back in charge.", "The habit pushed. You pushed back.", .proud),
        ("Well chosen.", "That’s time you get to keep.", .happy),
        ("Nice save.", "Each time you do this, the next one gets a little easier.", .cheer),
        ("You turned around.", "That’s the part that matters.", .happy),
        ("Clean exit.", "No scrolling, no regret.", .happy),
        ("Focus wins this one.", "Back to what you were doing.", .cheer),
        ("Look who’s in charge.", "Hint: it isn’t the algorithm.", .proud),
        ("Calm and done.", "No drama. Just a better choice.", .happy),
        ("Small win.", "Small wins are how big changes happen.", .happy),
        ("That felt good, right?", "Remember this feeling next time.", .happy),
        ("Back to the good stuff.", "Whatever you sat down to do.", .happy),
        ("Thank you.", "Signed, the part of you that wanted to focus.", .happy),
        ("Respect.", "You kept a promise to yourself.", .proud),
        ("That’s character.", "Scrolling was easier. You didn’t.", .proud),
        ("Self-respect looks like that.", "Choosing focus is a kind of kindness.", .proud),
        ("Ahh, quieter.", "Your brain thanks you for the break from the noise.", .happy),
        ("Nailed it.", "You saw the pull and didn’t follow it.", .cheer),
        ("Momentum.", "Ride it straight back into what you were doing.", .cheer),
        ("Good instincts.", "Trust them next time too.", .happy),
        ("That’s growth.", "The habit asked. You said no.", .proud),
        ("Look at that.", "The urge came and went, and you’re still here.", .happy),
        ("The feed will be fine.", "So will you.", .happy),
        ("Right on.", "Go do the thing you opened your laptop for.", .cheer),
        ("Your time, kept.", "Scrolled time never comes back. This did.", .happy),
        ("Steady.", "Breathe, close, carry on.", .happy),
        ("You’re building something.", "Each close is a brick in a better habit.", .proud),
        ("Back to you.", "The rest of your day just got a little clearer.", .happy),
    ]

    /// After the pause on a second or later reach within the hour, when it was harder.
    /// Never "twice": it may be the fifth time.
    static let turnedBackAgain: [Reward] = [
        ("That one was harder.", "You turned back anyway. That’s how habits change.", .proud),
        ("Tempted again. Still no.", "That’s real resilience.", .proud),
        ("Came back, still said no.", "The hardest kind of yes to yourself.", .proud),
        ("Persistent pull, persistent you.", "The habit keeps asking. You keep answering.", .proud),
        ("That one mattered most.", "Turning back when it’s hard is what rewires things.", .proud),
        ("Not easy. Done anyway.", "That’s the whole story of change.", .proud),
        ("Stubborn pull. Stubborner you.", "Love to see it.", .cheer),
        ("Wave ridden out.", "Urges rise, peak and pass. You let this one pass.", .proud),
        ("Proud of that one.", "It would have been easy to give in.", .proud),
        ("Hard moments count most.", "This is the close that builds the habit.", .proud),
        ("You held on.", "That’s what strength actually looks like.", .proud),
        ("Rough hour, right call.", "Be kind to yourself for the rest of it.", .proud),
        ("Still standing.", "The pull kept trying. You kept choosing.", .proud),
        ("Again, and again you chose.", "That’s the muscle getting stronger.", .proud),
        ("That took something.", "Especially this time.", .proud),
        ("Back, and back again.", "Every return that ends here is practice.", .proud),
        ("No easy one, that.", "You stayed with it and closed it.", .proud),
        ("The habit lost again.", "It hasn’t noticed you’ve changed yet.", .cheer),
        ("Steady under pressure.", "The pull was loud. You were steadier.", .proud),
        ("That’s the real work.", "Not avoiding the pull. Turning back from it.", .proud),
        ("One more turn back.", "On an hour like this, that’s a big deal.", .proud),
        ("Patience wins.", "Every no makes the next pull a little quieter.", .proud),
        ("Holding steady.", "This is what changing a habit feels like.", .proud),
        ("You chose again.", "That’s exactly how it gets easier.", .proud),
    ]

    /// After closing having picked "I need it": they had a reason ready and let it go.
    static let changedMind: [Reward] = [
        ("Changed your mind.", "That’s allowed, and it was the better call.", .proud),
        ("Didn’t need it after all.", "Good to notice before the minutes started.", .happy),
        ("Wrote it out, let it go.", "Sometimes saying why is enough.", .happy),
        ("Not this time.", "If it really matters, it’ll still be there later.", .happy),
        ("Good call.", "The reason didn’t hold up, and you noticed.", .proud),
        ("Later is fine.", "It can wait until the block is off.", .happy),
        ("Honest with yourself.", "That’s harder than it sounds.", .proud),
        ("Saved for later.", "Make a note and come back when you’re free.", .happy),
        ("Second thoughts, good ones.", "Writing it down showed you the answer.", .happy),
        ("You chose focus.", "Even with a reason ready, you let it go.", .proud),
    ]

    /// Moving on during the heads-up, before any pause. They may have closed the tab or
    /// just switched away, so these say "moved on", never "closed".
    static let turnedBackEarly: [Reward] = [
        ("Caught it yourself.", "No pause needed. That’s the habit changing.", .proud),
        ("All you.", "I only had to mention it.", .proud),
        ("That was quick.", "You moved on before the pause even came.", .cheer),
        ("Your call, and a good one.", "The heads-up was enough.", .happy),
        ("Back before it started.", "The feed didn’t even get going.", .happy),
        ("Self-made save.", "Nobody stopped you. You stopped.", .proud),
        ("Just a nudge needed.", "That’s exactly how it should feel.", .happy),
        ("No pause needed.", "You handled it before I had to.", .cheer),
        ("That’s the one.", "Turning back on your own is the whole point.", .proud),
        ("Smooth.", "A glance, a turn, back to it.", .happy),
        ("Heard and handled.", "One heads-up, and you were gone.", .cheer),
        ("That’s how it’s done.", "Notice, turn away, carry on.", .cheer),
        ("Look at you go.", "You didn’t need the pause at all.", .cheer),
        ("Quick turn.", "The best moment to stop is right at the start.", .happy),
        ("On your own terms.", "You decided, not the feed.", .proud),
        ("Perfect timing.", "Early is the easiest moment to walk away.", .happy),
    ]

    /// After the pause, for the feeling they named: something that meets it better than
    /// the feed would have.
    static let turnedBackBecause: [UrgeReason: [Reward]] = [
        .bored: [
            ("Boredom isn’t an emergency.", "Let it be. Good ideas often show up right after.", .happy),
            ("Go find something real.", "A stretch, a walk, a window. Anything but the feed.", .cheer),
            ("Bored is a signal.", "Your brain wants something new. Give it something real.", .happy),
            ("Let your mind wander.", "Not into a feed. Into a window, a walk, a thought.", .happy),
            ("Get up and move.", "Boredom fades fastest when your body moves.", .cheer),
            ("Find a small spark.", "A song, a stretch, a glass of water. Anything real.", .happy),
            ("The feed would’ve made it worse.", "Scrolling turns boredom into restlessness.", .happy),
            ("Bored and brave.", "Sitting with boredom is a quiet superpower.", .proud),
            ("Make it interesting.", "What could you do in the next five minutes?", .happy),
            ("Two minutes, offline.", "Step away and see what comes to mind.", .happy),
            ("Nice save.", "Boredom passes. A feed only keeps it going.", .cheer),
            ("Let it be boring.", "Your best thinking often starts right here.", .happy),
        ],
        .tired: [
            ("Rest for real.", "Eyes closed, shoulders down. The feed was never going to do that.", .happy),
            ("Good call.", "Close your eyes for a minute. You’ve earned it.", .happy),
            ("Tired is a signal.", "Not a failure. Give your brain some quiet.", .happy),
            ("Real rest, coming up.", "Water, a window, a few slow breaths.", .happy),
            ("Recharge properly.", "Scrolling drains. Stillness refills.", .happy),
            ("Be gentle with yourself.", "Two quiet minutes beat an hour of scrolling.", .happy),
            ("Step away for a bit.", "A short walk does more than any feed.", .happy),
            ("Breathe out.", "Let your eyes rest on something far away.", .happy),
            ("Drink some water.", "Tired brains are often thirsty brains.", .happy),
            ("Smart move.", "A tired brain needs quiet, not more input.", .proud),
            ("Stretch it out.", "Stand up, reach up, roll your shoulders.", .happy),
            ("Rest well.", "Come back when you’re ready. It’ll all still be there.", .happy),
        ],
        .stuck: [
            ("Now make it smaller.", "One tiny step. That’s all the next two minutes need.", .happy),
            ("Stuck means you’re close.", "It’s the hard part, and that’s where the good work is.", .proud),
            ("Just the next step.", "Not the whole thing. One sentence, one line, one move.", .happy),
            ("Shrink it down.", "What’s a version you could do badly in two minutes?", .happy),
            ("Good call.", "Avoiding it feels better for a minute and worse for an hour.", .happy),
            ("Write one line.", "Put the next step into a single sentence.", .happy),
            ("That’s brave.", "Facing the hard part is the whole job.", .proud),
            ("Talk it through.", "Explain the problem out loud, even to no one.", .happy),
            ("Start ugly.", "A rough first try beats a perfect plan.", .happy),
            ("Back at it, smaller.", "Pick the easiest piece and start there.", .cheer),
            ("The wall has a door.", "Find the smallest thing you can do right now.", .happy),
            ("Hard part, still here.", "And so are you. One piece at a time.", .proud),
        ],
        .anxious: [
            ("That took strength.", "Write it down. It gets lighter out of your head.", .proud),
            ("Breathe it out.", "The feed would only have added more noise.", .happy),
            ("You’re okay.", "Name what’s worrying you. Named things are smaller.", .happy),
            ("One thing at a time.", "You don’t have to solve it all right now.", .happy),
            ("Feet on the floor.", "Notice five things you can see. You’re here, and okay.", .happy),
            ("Gentle with yourself.", "An anxious mind needs calm, not more input.", .happy),
            ("Good choice.", "Scrolling numbs it for a minute, then brings it back louder.", .happy),
            ("Slow breath out.", "A long exhale tells your body it’s safe.", .happy),
            ("Put it on paper.", "Your mind doesn’t have to hold everything at once.", .happy),
            ("What’s in your control?", "Pick one small thing and do just that.", .happy),
            ("That was kind to yourself.", "Kindness is the right answer to worry.", .proud),
            ("A little lighter.", "One less thing feeding the worry.", .happy),
        ],
        .lonely: [
            ("Reach someone real.", "One message to someone you like beats any feed.", .happy),
            ("Say hi to someone.", "Pick one person. Send a short hello. That’s it.", .cheer),
            ("They’d love to hear from you.", "Really. People rarely mind a hello.", .happy),
            ("Real people, real warmth.", "A feed shows you people. A message reaches them.", .happy),
            ("Call someone.", "Two minutes of a real voice beat an hour of scrolling.", .happy),
            ("You’re not the only one.", "Lots of people feel this. Reach out to one of them.", .happy),
            ("Good call.", "The feed would have hidden the loneliness, not eased it.", .happy),
            ("Send that message.", "The one you’ve been meaning to send.", .cheer),
            ("Say it first.", "Someone would be glad to hear from you today.", .happy),
            ("Make someone’s day.", "A short message can do it, both ways.", .happy),
            ("Step outside.", "Even a short walk among people helps.", .happy),
            ("That was brave.", "Saying you feel alone is the first step out of it.", .proud),
        ],
    ]

    /// The line for turning back at the pause.
    /// - Having picked "I need it": the changed-mind set.
    /// - A repeat reach within the hour: the harder set, whatever they named.
    /// - Otherwise half the time a line for the feeling they named, half a general one, so
    ///   both sets get seen.
    @MainActor
    static func reward(for reason: UrgeReason?, visit: Int) -> Reward {
        if reason == .needed { return CopyDeck.draw(changedMind, deck: "reward.changedMind") }
        if visit > 1 { return CopyDeck.draw(turnedBackAgain, deck: "reward.again") }
        if let reason, let lines = turnedBackBecause[reason], Bool.random() {
            return CopyDeck.draw(lines, deck: "reward.\(reason.rawValue)")
        }
        return CopyDeck.draw(turnedBack, deck: "reward.any")
    }

    @MainActor
    static func rewardForTurningBackEarly() -> Reward {
        CopyDeck.draw(turnedBackEarly, deck: "reward.early")
    }
}

/// Deals lines from a shuffled deck per set, so nothing repeats until the rest of its set
/// has been seen, and a reshuffle never opens with the line that was just shown.
@MainActor
enum CopyDeck {
    private static var decks: [String: [Int]] = [:]
    private static var last: [String: Int] = [:]

    static func draw<T>(_ items: [T], deck key: String) -> T {
        guard items.count > 1 else { return items[0] }
        var deck = decks[key] ?? []
        if deck.isEmpty {
            deck = Array(items.indices).shuffled()
            // `removeLast` deals from the end, so keep the previous line away from it.
            if let previous = last[key], deck.last == previous {
                deck.swapAt(deck.count - 1, 0)
            }
        }
        let index = deck.removeLast()
        decks[key] = deck
        last[key] = index
        return items[index]
    }
}
