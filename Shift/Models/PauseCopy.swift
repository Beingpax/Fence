import Foundation

/// Every line Shift says at the pause and when someone turns back.
///
/// Lots of them, on purpose. The same sentence every time stops being read by the third
/// time, and a pause that's skimmed has no effect. Lines are dealt from a shuffled deck
/// (`CopyDeck`), so none repeats until all the others in its set have been shown.
///
/// The voice, for anyone adding lines:
/// - **A friend, not a warden.** Warm, a little wry, always on the person's side.
/// - **The urge is "the pull" or "the habit", never the person.** Shame makes people fight
///   the tool instead of the habit.
/// - **Short.** Titles under about six words; subtitles one or two plain sentences.
/// - **`{target}`** is replaced with the site or app, like "instagram.com".
/// - No exclamation marks in the pause. A little celebration is fine in rewards.
enum PauseCopy {
    typealias Line = (title: String, subtitle: String)

    // MARK: The pause

    /// The first reach within an hour: gentle, curious, inviting a single breath.
    static let firstReach: [Line] = [
        ("Take a breath.", "You reached for {target}. Before it pulls you in, check in with yourself."),
        ("Hey. Just a second.", "{target} will still be there. Let’s make sure you actually want it first."),
        ("One breath first.", "Your hand knew the way to {target} before you decided. Let’s decide now."),
        ("Pause here.", "That was quick. Was it you choosing {target}, or the habit?"),
        ("Hold on a moment.", "Notice the pull toward {target}. You can feel it without following it."),
        ("Breathe with me.", "Five seconds, then it’s your call. No judgement either way."),
        ("Let’s slow down.", "The feed is fast on purpose. You don’t have to be."),
        ("Quick check-in.", "Something sent you to {target}. Let’s find out what."),
        ("Not so fast.", "Give yourself one breath before {target} gets the next ten minutes."),
        ("Stay with me a second.", "The urge is loudest right now. Wait a moment and it gets quieter."),
        ("Here’s your moment.", "Right now you can still choose. In a minute, the feed chooses for you."),
        ("A small pause.", "You opened {target} on autopilot. Let’s switch the pilot back on."),
        ("Breathe in.", "Whatever you were doing before this is still waiting for you."),
        ("Hey, it’s okay.", "Everyone reaches for something. Let’s see what you were reaching for."),
        ("Before you go in.", "Think about how you want to feel when you close {target} again."),
        ("Let this one pass.", "Urges are waves. Watch this one rise, and let it roll by."),
        ("Take a beat.", "You were in the middle of something. Let’s not hand it to {target}."),
        ("Just breathe.", "Nothing’s wrong. You caught yourself, and that’s the hard part."),
        ("Wait a moment.", "The best decisions happen a few seconds after the first impulse."),
        ("Look up for a second.", "Away from the screen. One slow breath. Then choose."),
    ]

    /// The second reach within an hour: no surprise, no scolding, a longer breath.
    static let secondReach: [Line] = [
        ("Back again.", "That’s the pull, not you. Urges rise, peak and fade, usually within a minute. Ride this one out."),
        ("Round two.", "{target} is persistent today. So are you. Fifteen seconds, then choose."),
        ("Hello again.", "No shame in coming back. It usually means something’s unsettled. Let’s look at it."),
        ("The pull is back.", "That’s normal. Habits knock a few times before they give up."),
        ("Again? That’s okay.", "Every time you pause instead of scroll, the habit gets a little weaker."),
        ("Still thinking about it?", "Something keeps sending you to {target}. Let’s name it this time."),
        ("Let’s try this again.", "A slightly longer breath this time. The urge is already fading."),
        ("You’re back.", "Last time you turned around. You can do it again."),
        ("Same pull, new chance.", "You don’t have to win every time. Just this one."),
        ("Here we are again.", "Fifteen slow seconds. Notice what you’re actually feeling."),
        ("It’s calling again.", "{target} is built to be hard to resist. Resisting it is a skill, and you’re practising."),
        ("Breathe a bit longer.", "The second reach is usually the restless one. Let it settle."),
        ("One more breath.", "Whatever you’re avoiding is probably smaller than it feels."),
        ("It’s persistent today.", "So is the part of you that wants to get things done."),
        ("Let’s sit with it.", "The itch to check is strongest just before it fades."),
    ]

    /// The third reach and beyond: the pull is clearly strong, so be kinder and slower.
    static let laterReach: [Line] = [
        ("Third time this hour.", "The pull is strong today, and that’s okay. Sit with it for thirty seconds, then choose."),
        ("It’s a hard day for this.", "Some days the pull is louder. Be gentle with yourself, and stay a while."),
        ("Let’s really stop.", "Thirty seconds. No feed, no task. Just you and your breath."),
        ("Something’s up.", "Reaching this often usually means you need something. Let’s find out what."),
        ("You keep coming back.", "That’s not weakness, it’s a signal. Listen to it for thirty seconds."),
        ("Slow all the way down.", "Hands in your lap. Breathe. Let the restlessness pass through."),
        ("This one’s a big wave.", "Big waves still pass. Ride it out with me."),
        ("Let’s take a real pause.", "{target} won’t fix what you’re feeling right now. Let’s find something that will."),
        ("Hey. Step back.", "Look away from the screen. Find something far away to rest your eyes on."),
        ("The feed can wait.", "It isn’t going anywhere. Neither are you. Thirty seconds."),
        ("Your brain needs a break.", "Coming back this often is a sign it’s running on empty. Give it thirty quiet seconds."),
        ("Still here. Still with you.", "No lecture. Just a longer breath this time."),
        ("Let’s be honest.", "This isn’t about {target}. Something else needs your attention. Breathe and find it."),
    ]

    @MainActor
    static func pause(visit: Int, target: String) -> Line {
        let (deck, lines): (String, [Line]) = switch visit {
        case ...1: ("pause.first", firstReach)
        case 2: ("pause.second", secondReach)
        default: ("pause.later", laterReach)
        }
        return fill(CopyDeck.draw(lines, deck: deck), target: target)
    }

    // MARK: Turning back

    /// Turning back with no answer given, on a first reach.
    static let turnedBack: [Line] = [
        ("That’s the one that counts.", "You chose your work over the feed."),
        ("Nice save.", "Every time you do this, the next one gets easier."),
        ("Back to it.", "Future you just said thank you."),
        ("Look at you.", "Walking away is a muscle. You just used it."),
        ("That’s how it’s done.", "One close at a time. That’s the whole method."),
        ("Good call.", "The feed lost this round."),
        ("Proud of you.", "That took more than it looked like."),
        ("There you go.", "Quietly brilliant."),
        ("Nicely done.", "You noticed, you chose, you closed. That’s the habit."),
        ("Way to go.", "Your attention is yours again."),
        ("Small win.", "Small wins are how big changes happen."),
        ("That’s the move.", "Close, breathe, back to it."),
        ("Back in control.", "The habit pushed. You pushed back."),
        ("You did it.", "No willpower drama. Just a calm close."),
        ("Love that.", "That’s what changing a habit actually looks like."),
        ("Strong choice.", "Ten minutes of your life, saved."),
        ("Feed 0, you 1.", "Keep that score going."),
        ("Clean break.", "Nothing lost, everything kept."),
        ("That’s growth.", "Not long ago, that might have been an hour."),
        ("Easy does it.", "See? It didn’t even hurt."),
        ("Well chosen.", "Your day just got a little better."),
        ("Brilliant.", "The pull was real, and you still turned around."),
        ("That’s you, not the habit.", "Every close teaches your brain a new default."),
        ("Right on.", "Go do the thing you actually opened your laptop for."),
        ("High five.", "Seriously, that’s worth celebrating."),
        ("Look who’s in charge.", "Hint: it isn’t the algorithm."),
        ("Beautiful.", "Calm, deliberate, done."),
        ("One less scroll.", "That adds up faster than you think."),
        ("You’re building something.", "Each close is a brick in a better habit."),
        ("That’s the spirit.", "Back to what matters."),
        ("Nailed it.", "You caught it early. That’s the best time."),
        ("Back on track.", "Your work missed you."),
        ("Quiet victory.", "Nobody saw it, and it still counts."),
        ("Done and dusted.", "The feed will survive without you."),
        ("Momentum.", "Ride it straight back into your work."),
        ("That felt good, right?", "Remember this feeling next time."),
        ("Self-respect looks like that.", "Choosing focus is a kind of kindness to yourself."),
        ("Ahh, much better.", "Your brain thanks you for the quiet."),
        ("That’s the habit forming.", "It gets easier from here. Promise."),
        ("Excellent.", "Your attention is the most valuable thing you own. You kept it."),
        ("Smooth.", "That was almost effortless. That’s the goal."),
        ("Back to you.", "The rest of your day just got a little brighter."),
        ("You turned around.", "That’s the whole game, right there."),
        ("Well done.", "You didn’t need it. You knew that."),
        ("That’s a keeper.", "Do that again tomorrow."),
        ("Calm and clear.", "Back to what you came here to do."),
        ("Respect.", "Not everyone can do what you just did."),
        ("Good instincts.", "Trust them next time too."),
        ("Look at that.", "The urge came and went, and you’re still here."),
        ("Score one for focus.", "Keep the streak going in your head."),
        ("That’s the way.", "The feed will be fine. So will you."),
        ("Just like that.", "No drama. Just a better choice."),
        ("Wonderful.", "You protected your time."),
        ("You’re getting good at this.", "It shows."),
        ("That’s real progress.", "Not perfect. Better."),
        ("Back to the good stuff.", "The stuff that actually matters to you."),
        ("Clear head ahead.", "Nothing pulling at you now."),
        ("Thank you.", "Signed, the version of you that gets things done."),
        ("Nicely caught.", "You spotted the habit before it took over."),
        ("That’s character.", "Doing the right thing when it isn’t the easy thing."),
    ]

    /// Turning back on a second or later reach, when it was clearly harder.
    static let turnedBackHard: [Line] = [
        ("That one was harder.", "You turned back anyway. That’s exactly how habits change."),
        ("Twice tempted, twice strong.", "That’s real resilience."),
        ("You came back and still said no.", "That’s the hardest kind of yes to yourself."),
        ("Persistent pull, persistent you.", "The habit is losing."),
        ("That one counts double.", "Turning back when it’s hard is what rewires things."),
        ("Tough round, well played.", "The urge is getting weaker. Keep going."),
        ("That was the hard one.", "And you handled it."),
        ("Not easy. Done anyway.", "That’s the whole story of change."),
        ("Stubborn pull. Stubborner you.", "Love to see it."),
        ("Big wave, ridden out.", "The next one will be smaller."),
        ("Proud of that one.", "It would have been so easy to give in."),
        ("Hard days count most.", "This is one of the closes that builds the habit."),
        ("You held on.", "That’s what strength actually looks like."),
        ("Rough moment, right call.", "Be kind to yourself for the rest of today."),
        ("Still standing.", "The feed kept trying. You kept winning."),
    ]

    /// Turning back after naming what they were really after.
    static let turnedBackBecause: [UrgeReason: [Line]] = [
        .bored: [
            ("Nice save.", "Go find something real. Even a stretch beats the feed."),
            ("Boredom isn’t an emergency.", "Let it be. Good ideas often show up right after."),
            ("Go make it interesting.", "Walk, stretch, look out of a window. Your mind will thank you."),
            ("Let your mind wander.", "Not into a feed. Into a window, a walk, a thought."),
            ("Bored is okay.", "It’s your brain asking for something new. Give it something real."),
            ("Something better awaits.", "Two minutes of real life beat twenty of scrolling."),
            ("Good call.", "The feed would only have made the boredom louder."),
            ("Get up and move.", "Boredom melts fastest when your body moves."),
            ("Find a small spark.", "A song, a stretch, a glass of water. Anything real."),
            ("Bored and brave.", "Sitting with boredom is a quiet superpower."),
        ],
        .tired: [
            ("Good call.", "Close your eyes for a minute. You’ve earned it."),
            ("Rest for real.", "Eyes closed, shoulders down. The feed was never going to do that."),
            ("Your brain says thanks.", "Real rest, not more input."),
            ("Go easy on yourself.", "Tired is a signal, not a failure."),
            ("A real break, coming up.", "Water, a window, a few slow breaths."),
            ("Recharge properly.", "Scrolling drains. Stillness refills."),
            ("Smart move.", "Tired brains deserve quiet, not noise."),
            ("Breathe out.", "Let your eyes rest on something far away."),
            ("Be gentle with yourself.", "Two quiet minutes will do more than an hour of scrolling."),
            ("Rest well.", "Come back when you’re ready. Your work will wait."),
        ],
        .stuck: [
            ("Now make it smaller.", "One tiny step. That’s all the next two minutes need."),
            ("Stuck is normal.", "It means you’re at the hard part. That’s where the good stuff is."),
            ("Back to the wall.", "Find the smallest crack. Start there."),
            ("Just the next step.", "Not the whole thing. One sentence, one line, one move."),
            ("Hard work, real you.", "The feed would only have made it harder to come back."),
            ("You’re closer than you think.", "Hard parts always look like walls from up close."),
            ("Shrink it down.", "What’s a version of this you could do badly in two minutes?"),
            ("Good call.", "Avoiding it feels better for a minute and worse for an hour."),
            ("Write one thing down.", "The first step is always the smallest."),
            ("That’s brave.", "Facing the hard part is the whole job."),
        ],
        .anxious: [
            ("That took strength.", "Write it down. It gets lighter out of your head."),
            ("Breathe it out.", "The feed would only have added more noise."),
            ("You’re okay.", "Name what’s worrying you. Named things are smaller."),
            ("Put it on paper.", "Your mind doesn’t have to hold everything at once."),
            ("One thing at a time.", "You don’t have to solve it all right now."),
            ("Gentle with yourself.", "An anxious mind needs calm, not more input."),
            ("Good choice.", "Scrolling numbs it for a minute, then brings it back louder."),
            ("Feet on the floor.", "Notice five things you can see. You’re here, and you’re okay."),
            ("That was kind to yourself.", "Kindness is the right answer to worry."),
            ("Lighter already.", "It’s out of the feed’s hands now."),
        ],
        .lonely: [
            ("Go reach someone real.", "One message to someone you like beats any feed."),
            ("Connection is a text away.", "Pick one person. Say hi. That’s it."),
            ("They’d love to hear from you.", "Really. People rarely mind a hello."),
            ("Real people, real warmth.", "A feed only shows you people. A message reaches them."),
            ("Call someone.", "Two minutes of a real voice beat an hour of scrolling."),
            ("You’re not the only one.", "Lots of people feel this. Reach out to one of them."),
            ("Good call.", "The feed would have hidden the loneliness, not eased it."),
            ("Send that message.", "The one you’ve been meaning to send."),
            ("Someone’s thinking of you.", "Be the one who says it first."),
            ("Make someone’s day.", "A short message can do it, both ways."),
        ],
    ]

    @MainActor
    static func reward(for reason: UrgeReason?, visit: Int) -> Line {
        if let reason, let lines = turnedBackBecause[reason] {
            return CopyDeck.draw(lines, deck: "reward.\(reason.rawValue)")
        }
        return visit > 1
            ? CopyDeck.draw(turnedBackHard, deck: "reward.hard")
            : CopyDeck.draw(turnedBack, deck: "reward.any")
    }

    private static func fill(_ line: Line, target: String) -> Line {
        (line.title.replacingOccurrences(of: "{target}", with: target),
         line.subtitle.replacingOccurrences(of: "{target}", with: target))
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
