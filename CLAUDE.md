# Shift: context for Claude

Shift is a **macOS-only, local-AI app and website blocker**: Cold Turkey-level strictness, but it understands what's on screen. Read `PRD.md` for the full spec; this file is the working memory of decisions already made.

Local folder: `~/Shift Focus`. Repo: https://github.com/Beingpax/Shift-Focus (branch `main`). Owner: Prakash Joshi Pax (`Beingpax`).

## Current status (read first)

- **Blocking is built on habit psychology** as of 23 Nov 2026: a rule match gets a
  full-screen pause, not a ladder of nudges.
- **There are no focus goals and no AI intent checks.** The user had them removed
  entirely on 23 Nov 2026: the block's goal field, `IntentClassifier`,
  `IntentNudgeMonitor`, `ScreenTextReader`, `AXTextReader` and the Screen Recording
  permission are gone. Detection is the block lists plus the feed-keyword drift hint.
  Don't bring any of it back without asking. See "The pause" below; read it before
  touching enforcement or any copy the user sees.
- **The app is organised around blocks, not sessions** as of 22 Nov 2026. This replaced the
  original focus-session model. See "The block model" below; it is the most important
  thing to understand before changing anything.
- **Builds clean** with zero errors and zero warnings, including under
  `SWIFT_STRICT_CONCURRENCY = complete`, which is now switched on in the project.
- **Runtime verification is still thin.** The app launches and stays up, and the schedule
  and lock maths have standalone tests (`./Tools/run-block-tests.sh`, 22 assertions). The
  UI flows have not been walked through by hand.
- Built: main window (Dashboard, Blocks, Activity), block editor, menu bar popover,
  the full-screen pause with time-of-day wallpapers, reward and hint HUD, weekly review on the
  Dashboard, onboarding, launch at login,
  watchdog pair, and quit and Trash protection.
- Active detection uses app, website, and path rules. Optional nudges use window-title keywords.
- **The binary has two entry points.** `Shift` is the app; `Shift --watchdog` is the
  headless watchdog. `main.swift` branches, which is why `ShiftApp` has no `@main`.

## Build and run

```bash
xcodebuild -project Shift.xcodeproj -scheme Shift -configuration Debug -destination 'platform=macOS' build
```

- Run from Xcode with Cmd+R. Shift is an `LSUIElement` menu bar app (◎ icon), with no Dock icon.
- Test without side effects: Settings → Previews has the pause (first, second and third reach), the turning-back reward, and the soft drift hint.
- Real test: switch on a block listing `instagram.com` or `youtube.com/shorts`, then open it in Safari or Chrome. The pause should cover the screen within about a quarter of a second of pressing Return, usually before the page has loaded.
- Shift requests Accessibility for window titles and browser addresses.
- **Signing is load-bearing for permissions.** `DEVELOPMENT_TEAM = V6J6A3VWY2` is set on both configurations, so builds are signed with a real identity. Do not let this fall back to ad-hoc. macOS keys TCC grants to the designated requirement, and an ad-hoc signature puts the binary's `cdhash` in that requirement, so **every rebuild silently voids the Accessibility grant** and the app reports "not granted" while System Settings still shows it enabled. Verify with `codesign -d -r- <app>`: the requirement must name the certificate, not a `cdhash`. If a grant ever does go stale, `tccutil reset Accessibility com.beingpax.Shift` and grant it again.
- Automated GUI testing needs Accessibility and Screen Recording granted to the terminal running Claude Code. Without them, `osascript` UI scripting fails with -1719 and `screencapture` fails outright, so shield verification has to be manual.

## Verification checklist (not yet walked through by hand)

1. **Menu bar.** Icon appears; the count next to it matches the number of active blocks.
2. **Main window.** Menu bar → Open Shift. Create a block, add sites and apps, save.
3. **Blocking.** Switch the block on, visit a listed site in Safari and Chrome. The pause
   should cover every display almost at once. Choices unlock after 10 s (20 s on the
   second reach). Every answer except "I need it" closes only the tab, then shows the
   reward. "I need it" appears only when the block allows breaks: type a reason, pick 1 or
   2 minutes, and only that site opens; the block stays on and still blocks everything
   else. A third reach within an hour waits 30 s and plays
   the deeper chime. Check the wallpaper matches the time of day.
4. **Schedules.** Set a window that starts a minute from now and confirm it self-activates.
5. **Nudges.** With a block active and nudges enabled, open an unblocked window whose title contains a configured feed keyword.
6. **Locks.** Each of duration, until-time, random-string and restart. Check that the
   switch, the editor and Delete all refuse while locked.
7. **Breaks.** Enable breaks, hit the block, take a break, confirm the block goes quiet and
   comes back.
8. **Quit protection.** Cmd+Q with a locked block should explain itself. `kill -15` should
   be ignored; `kill -9` is expected to win.
9. **Watchdog.** With a lock engaged, `pkill -f 'Shift.app/Contents/MacOS/Shift$'`. Shift
   should return within ~5 s. Also try moving the app to the Trash.
10. **Onboarding.** `defaults delete com.beingpax.Shift Shift.hasCompletedOnboarding.v1`.
11. **Clean up after testing:** `launchctl bootout gui/$UID/com.beingpax.Shift.watchdog`,
    delete `~/Library/LaunchAgents/com.beingpax.Shift.watchdog.plist`, and remove
    `~/Library/Application Support/Shift/`.

Run the model tests any time with `./Tools/run-block-tests.sh`.

## The block model

A **block** is the unit of everything. It owns:

- a **list**: website domains, paths and apps;
- a **schedule**: Always, Schedule, or None. None uses the existing `.manual(minutes:)`
  storage and starts timed runs from the block’s menu bar context menu;
- a **lock**: `none`, `duration`, `untilTime`, `randomString`, or `restart`, which engages
  the moment the block is switched on;
- **breaks**: optional, with two two-minute pauses per local day.

Several blocks can be active at once. `BlockEvaluator` asks each active block in order and
the first with an opinion wins. A block is active when it is enabled or locked on, is
inside its schedule, and is not on a break.

Rules that are easy to get wrong, and are covered by the tests:

- Schedule windows may run past midnight; the window belongs to the day it started on.
- An `untilTime` lock set to a time already past today rolls to tomorrow.
- A `restart` lock releases after the boot session changes. Saves from older builds
  use their stored boot time during migration.
- While locked, a block may be edited only to become stricter. Entries can be added,
  and the schedule, break settings and lock method are frozen.
- `Finder`, System Settings and Shift itself are never blocked, so a bad allow-list can't
  lock someone out of fixing it.

## Threading rules

`SWIFT_STRICT_CONCURRENCY = complete` is on. Keep the build warning-free under it.

- `AppModel`, `BlockStore` and the window controllers are `@MainActor`. SwiftUI reads them.
- Anything that talks to another process runs off the main actor and is awaited:
  Accessibility reads (`WindowInspector`, 0.5 s messaging timeout) and observer
  registration (`AddressObserver`).
- `ContextMonitor` drops overlapping samples rather than queueing them, so a slow reading
  can't build a backlog behind it.
- Block writes are debounced and encoded off the main actor. `saveNow()` is for the cases
  where losing the write would hand the user a way out.

## Product decisions (don't relitigate without asking)

- **Onboarding creates the first block** from the user's choices. Add Block opens a blank editor.
- **The app picker is in-app.** `InstalledApps` scans the application folders once, off the
  main actor, and caches icons. Don't send people to an open panel.
- **Explicit lists contain websites, paths and apps.** Only a matching rule can raise the pause.
- **One window.** Settings is a section of the main window, not a `Settings` scene, so a
  menu bar app never puts two windows on screen. `MainSection` drives the sidebar, the
  model owns the selection, and Cmd+, opens the window at Settings. Don't reintroduce
  `SettingsLink`; it needs a `Settings` scene and there isn't one.
- **The menu bar popover is one fixed height.** Switching a block on must not resize it.
  The "What Shift sees" live context panel (`LiveContextView`) and the tinted mark down the
  left of an active row were both removed on 23 Nov 2026 at the user's request: the panel
  made the popover grow the moment Shift started watching, and the mark read as a stray
  blue bar beside the block's name. The switch and the status line say enough. Don't add
  anything to the popover that appears only while a block is on.
- **Blocks, not sessions.** A timer can't express "never Instagram" or "no games on
  weeknights". The old `FocusSession`, `BlockRules` and `Strictness` types are gone.
- **Locking and friction are different things.** The lock decides whether the switch works.
  Friction decides what the pause does when you hit it. Don't merge them.
- **The app icon is generated, not drawn by hand.** `Tools/make-icon.swift` renders every size and rewrites the appiconset's `Contents.json`. Edit the script, not the PNGs.
- **The nudge character is Flop, an invented creature, drawn in code.**
  `UI/NudgeCharacterView.swift` renders it in one `Canvas` pass driven by one clock. No
  image assets, no 3D, no dependency: crisp at any size, kilobytes instead of megabytes,
  and it can blink.
  - **The ears carry the escalation**, in pure silhouette: perked and fluttering, one
    cocked back, then both pinned flat out. You can read the rung from the corner of your
    eye without resolving a single facial feature. If you change one thing about the
    expressions, change `earAngle`. Everything else only confirms what the ears said.
  - **The dark outline is load-bearing.** A tinted `ink` stroke around every shape is the
    whole difference between a designed mascot and a gradient blob with eyes on it. Each
    mood carries its own ink — one black outline across all three reads as a printed
    sticker. Don't remove it.
  - **A being, not an object, and invented rather than real.** Both halves were tested the
    long way: rendered 3D art of a boy, a hand-drawn boy, a cat, then a run of faceless
    objects (plant, gauge, lock, candle). The boy fell into the uncanny valley; the objects
    stopped being someone you could feel anything about. Don't "improve" it toward realism
    and don't swap the creature for a thing.
  - Idle motion is not decoration, and **every mood gets all of it**: the bob, the sway,
    an ear flutter, a jittered blink (roughly every third a quick double), and eye
    saccades on top of the slow pupil drift. Eyes that only glide look painted on; a real
    one snaps somewhere and holds. Both the blink and the saccade intervals are jittered
    on purpose — fixed ones read as a metronome.
  - The HUD sits **top right, under the menu bar**, where macOS already puts things that
    want attention without taking it. **Flop stands to the left of the card, and the card's
    top edge sits on the tips of his ears**, with his feet hanging below it. The row aligns
    on `NudgeCharacterView.earTopInset()`, not on his frame: the frame keeps empty air above
    the ears for the flutter, so aligning on it put the card level with nothing. The top
    padding gives back what the ears take, which keeps the card under the menu bar where a
    banner sits. The pair **arrives and leaves exactly like a notification banner**: in from beyond the right edge, and back out the same way when it is dismissed
    or times out. The card never simply vanishes in place. The panel itself no longer
    fades; the SwiftUI card owns both halves of the movement, and `NudgeHUDView.isLeaving`
    is how the controller starts the exit (a new root view, so the slide-out animates
    without a shared observable). Under Reduce Motion both ends become a cross-fade.
  - **Three sounds** (`Enforcement/NudgeSound.swift`, `Resources/Sounds/`): `pause` (a soft
    singing-bowl chime, an invitation, never an alarm), `reward` (a bright rising glass bell
    when you turn back) and `shield.m4a`, played by `playDeep()` (a calm deep chord in place
    of the chime from the third reach: firmer, not louder).
    Polished chimes, not creature voices: a cartoon-creature set was tried and rejected.
    Generated with ElevenLabs sound effects, trimmed and loudness-matched with ffmpeg. Soft
    hints stay silent. Settings → Nudges → "Sounds" switches them all off.

- **Name:** "Shift", subtitle "Local App & Website Blocker".
- **No Dock icon by default,** but there is a "Show Shift in the Dock" switch in Settings → General that flips the activation policy at runtime. `LSUIElement` keeps the default as menu-bar-only.
- **Platform:** Apple Silicon Macs running macOS 26 or later.
- **Detection stays local.** Read browser addresses through Accessibility. Match enabled app, website, and path rules before considering a title-based nudge.
- **The pause is the only full-screen surface.** It replaced two things. The three-nudge
  ladder let the feed pay out for 25 seconds, trained people to tune Flop out, gave nothing
  for turning back, and reset on every tab switch. The separate shield (a 10-second wait
  plus 20 typed words on the third reach) was merged into the pause at the user's request:
  one screen that simply waits longer each time. See "The pause" below.
  - **In a browser, close the tab; anything else, quit it.** Quitting the whole browser
    punished the wrong thing. Let the user respond when an app shows a quit confirmation.
  - **The backdrop is a real photograph that follows the clock** (`PauseBackdrop`,
    `DayPeriod`): green landscapes at sunrise (05–09), late morning (09–13), afternoon
    savanna (13–17), sunset (17–20:30) and the Milky Way at night. All Unsplash License, see
    `CREDITS.md`. Green land, not desert: the user rejected dunes. A hand-rolled gradient
    always looks hand-rolled at this size, and matching the light outside makes the pause
    feel like a window, not a wall. Each period has its own scrim, heavier for bright
    daylight, so white type always reads (tuned by measuring each photo where the title
    sits; none ends up above about 0.42 of full white). The panel is frost plus a dark wash.
  - **It moves like a place, not a poster.** The photo pulls back from a slight zoom and
    then drifts for 40 s; the badge, title, subtitle and panel rise in one after another;
    the choices light up in sequence when the breath ends; answers slide in. Reduce Motion
    turns all of it into cross-fades.
  - **No progress indicator anywhere.** No "pause 2 of 3" and no dots. A tally made the
    whole thing read as a machine keeping score.
  - Only confident blocks reach the pause; soft hints never do. Default to allow on work apps when unsure.
- **Locked mode:** you can't end the session or quit Shift early.
- **Honesty:** an admin can always win. We sell friction, not a prison.

## Hard platform limits (researched, don't rediscover)

- **Screen Time frameworks do not exist on macOS.** FamilyControls, ManagedSettings and DeviceActivity are iOS and iPadOS only. There is no OS-level app shield to borrow, which is exactly why enforcement is app-level plus a watchdog, and why the honesty clause exists.
- **Socket-level network filtering is hostname-only.** HTTPS hides the path, so a `NEFilterDataProvider` can never do path-aware blocking. It is an M3 backstop, not a detection tier.
- **The macOS 26 full-URL filter is unusable for us.** It requires a Bloom filter plus a Private Information Retrieval *server* plus a dedicated entitlement. A server contradicts the local-only rule. Rejected, documented in PRD §10.2.
- **Foundation Models context is about 4,096 tokens** covering instructions, prompt, output and tool definitions together. Trim page text to roughly 2,500 tokens. Never send a whole page.
- **Chromium and Electron build accessibility trees lazily.** Chrome needs `AXEnhancedUserInterface` set on its application element; Electron needs `AXManualAccessibility`. Confirm success by reading the attribute back, because Chrome returns not-implemented even when it worked, and retry after about 150 ms because the tree fills asynchronously.
- **Don't try to render the character live, or in Blender.** Two routes were explored and
  rejected. Live 3D (RealityKit/SceneKit) means standing up a Metal renderer for a figure
  that is on screen for five seconds, against the app's whole low-energy argument — and
  RealityKit cannot load animations from Blender's USD export anyway, so the pipeline would
  run Blender → FBX → Reality Converter → USDZ by hand. Posing a rig in Blender (the free
  CC-BY Snow rig was tried end to end, and it does render headlessly) produces a character
  nobody asked for: Snow is a lean, realistically-proportioned adult in a grey t-shirt, and
  no amount of lighting turns him into a stylised kid. Flat rendered artwork is the answer.
- **Continuous screen capture is the expensive path.** Rewind shut down in December 2025 with a reputation for cooking MacBooks, and Screenpipe users report CPU spikes to 700% on an M3 Max. This is why OCR is change-gated and never on a timer.

## Competition (as of Nov 2026)

Intent-aware blocking has shipped elsewhere, so it is not a differentiator on its own. PRD §5 has the full table.

- **FocusDragon:** screenshots judged against your goal, acts after two consecutive off-task checks (the same hysteresis design we built), daemon-level enforcement, $4.99 once for Pro with the AI sold at $3.99–14.99 a month.
- **Focusing App:** local, judges each page, and removes off-intent *feed items* before they render. Ahead of us on in-page filtering. Subscription with daily focus-time caps.
- **Fomi:** window titles only, $29 once. **Meoz:** goal vs browser context. **Intentional / Flow State:** intensity varies by app.
- **Cold Turkey:** still the strictness benchmark at $39–45 once, using a root daemon plus hosts and DNS interception, and it blocks its own uninstall.

**Our wedge:** local-only AI, no subscription for the AI, nothing to download, Cold Turkey strictness, and a defensibly lower energy cost because we prefer exact text over pixels.

## Architecture

```
Shift/
├── App/            main (entry point branch), ShiftApp (MenuBarExtra + Settings),
│                   AppDelegate (quit protection), AppModel (@Observable, @MainActor engine)
├── Models/         Block (+ BlockList, BlockSchedule, ScheduleWindow, BlockLock, BreakPlan,
│                   BlockTint), BlockStore (persistence, locking, CRUD),
│                   ScreenContext, Verdict, ActivityEvent, DistractionPreset,
│                   Urge (UrgeReason, UrgeLog: every reach, plus if-then plans),
│                   PauseCopy (every line at the pause and on turning back, + CopyDeck)
├── Detection/      ContextMonitor (async sampling), AddressObserver (AX notifications),
│                   WindowInspector (AX),
│                   Browser (browser identities)
├── Intelligence/   BlockEvaluator (tier 0), Hysteresis
├── Enforcement/    PauseController + PauseView + PauseBackdrop (DayPeriod), TabCloser,
│                   NudgeSound, GuardState,
│                   LaunchAtLogin, WatchdogService, WatchdogRunner
└── UI/             DesignSystem (Theme, BlockBadge), Design/ (Materials, Controls),
                    MenuBarView, SettingsView (a pane, not a scene), NudgeHUD,
                    PermissionsManager, Main/ (MainWindowController, MainWindowView +
                    MainSection, DashboardView + WeekPanel, BlockEditorView + BlockInspector +
                    AppPickerView), Onboarding/
```

### The design language
Modelled on IINA: translucent chrome, depth from material weight rather than shadows, and
generous spacing. Three rules hold it together.

1. **Nothing is opaque** unless Reduce Transparency asks for it. The window, the sidebar,
   the cards and the popover are all `NSVisualEffectView` materials, via `Surface` and
   `VisualEffect` in `UI/Design/Materials.swift`. The window itself sets `isOpaque = false`
   and a clear background so the content can paint its own.
2. **Controls are Shift's own**, in `UI/Design/Controls.swift`: `SegmentedSelector`,
   `ShiftSwitch`, `OptionCard`, `TimeField`, `NumberStepper`, `DayPicker`, `Chip`,
   `ShiftTextField`, and the `shiftProminent` / `shiftSoft` button styles. Reach for these
   before a stock control, so the app reads as one thing.
3. **Structure comes from `Panel` and `PanelRow`**, not `Form`. Tint is carried by thin
   strokes and content, never by large filled rectangles.
4. **Page titles are `PageHeader`, inside the content.** Never use a `.principal` toolbar
   item: macOS 26 renders it as a capsule floating in the middle of the title bar. The
   title bar is for window controls and the one primary action.
5. **The sidebar is hand-built** from `SidebarRow`, not `List(selection:)`. The stock
   sidebar style paints a solid accent capsule and renders SF Symbols in multicolour,
   neither of which matches anything else here. Each section carries its own tint.

The pause is a photograph, not a material, so it needs neither. The nudge card uses
`NotificationGlass` (`NSGlassEffectView`), the same surface macOS draws notification banners on,
so a nudge looks like it belongs beside them.

### Design system
All spacing, radii, verdict colours and glass surfaces come from `Theme` and `glassCard()` in
`UI/DesignSystem.swift`. Two rules there are not optional: every glass surface falls back to an
opaque material under Reduce Transparency, and every animation falls back to a cross-fade under
Reduce Motion.

Flow: `AppModel.engineTick` (1 s) decides which blocks are active and starts or stops
detection → `ContextMonitor` sample (on every `AddressObserver` event, plus a 1.5 s poll) →
`AppModel.handle` → `BlockEvaluator` over the active blocks → `Hysteresis` (2 consistent
readings, the second requested 150 ms after the first) → `beginReach` → `PauseController`
→ `handlePause` → close the tab (or start a break), reward, record.

### The pause
Every choice here comes from habit research. Check changes against these, and don't
relitigate them without asking:

- **Catch the cue, before the reward.** `AddressObserver` subscribes to the front app's
  Accessibility notifications (focused element, title, window, `AXLoadComplete`), so
  pressing Return wakes a sample within ~0.1 s. Value-changed is deliberately *not*
  observed: it fires on every keystroke in every text field. A feed that never pays out
  stops being worth reaching for, which is why speed matters more than anything else.
- **Full screen, no Flop.** `PauseController` covers every display with `PauseBackdrop`
  and locks out the Dock, menu bar and Cmd+Tab. An earlier version covered only the
  browser window with Flop on a frosted panel; the user rejected it because the page
  stayed visible around it. Flop appears only afterwards, in the reward card.
- **One breath, then one honest question, one thing at a time.** During the breath there
  is no panel: only `ConstellationBreath`, chosen by the user from six HTML studies. On
  the out-breath the stars gather into a tight knot with a warm glow; breathing in, they
  open into a wide sky at three depths (near stars travel furthest, which reads as
  drifting forward) and thin lines draw themselves into a constellation, retracting as the
  breath empties. Warm and cool whites twinkle on their own clocks, the sky turns slowly,
  and a shooting star passes every 13 s or so. One `Canvas` at 30 fps, stars generated once
  from a fixed seed and stamped from pre-drawn glows. The breath is computed from the
  clock: in over 3 s, out over 2 s. Under it, **a bar that empties, not a countdown**:
  10 s, 20 s on the second reach, 30 s from the third, drained by one linear animation
  **from the right, anchored at its leading edge** (stepped once a second under Reduce
  Motion). It empties one way, like every other progress bar on the platform; pulling away
  from the middle in both directions at once was wrong and the user caught it. Digits invited
  counting; the bar is read at a glance and forgotten. The "Breathe in / and let it go"
  cue is gone with them at the user's request — the constellation already opens and
  gathers in time with the breath, and words only ask to be obeyed. Rejected on
  the way: rippling rings, a glass orb with orbiting motes, and several organic blobs
  (opaque, foggy, then a translucent drop the user hated). When it ends, the orb grows into the question panel
  (`matchedGeometryEffect`), the question reveals, and six feeling chips arrive one after
  another. **The question must be answerable by the chips.** It is "What's pulling you
  here?": the chips name a state ("I'm bored", "This is hard"), so the earlier "What were
  you hoping it would give you?" asked for a reward and left every answer reading like a
  non-sequitur. It asks what is behind the reach, and keeps the pull as the subject rather
  than the person — "why were you distracted" would put the blame back on them. Each chip is one short word and a white symbol; the longer description shows
  only on hover, in a single helper line, and 1–6 on the keyboard pick them. Nothing sits
  under the question but the chips: "Pick the closest one, there's no wrong answer" was
  cut as unnecessary. Choosing one
  replaces the question with its answer, and **there is no way back**: the only thing left
  is the close button. **It is the one solid white button, with near-black text, from the
  moment the question opens** — not only after a feeling is picked: turning back has to be
  the easiest thing on the screen. The one exception is "I need it", where the break
  buttons are what's being offered and a white button beside them would fight for the same
  job. The close button sits outside the panel, never waits, and answers to Return. Sources: GOV.UK's
  one-thing-per-page, Hick's law, one sec's breath-then-choice.
- **Neutral glass, sidebar-style icon tiles.** Cards, panel and buttons are white glass
  with a dark wash under the frost so they read on every backdrop. Only the feeling icons
  carry colour, as solid system-colour tiles drawn exactly like the sidebar's
  (`SidebarIconTile`, which now takes a `size`): yellow, indigo, orange, teal, pink, green.
  Tinted, semi-transparent circles were rejected. The user rejected fully
  colour-coded chips, and white-only symbols, and the teal/orange/purple tints in Settings
  and the week panel (as looking AI-generated). Settings and Dashboard panels stay neutral.
- **Words arrive, they don't switch on.** Every line on the pause reveals letter by letter,
  rising out of a soft blur (`RevealRenderer`, a `TextRenderer`, via `revealOnAppear`).
  Text that changes in place (the hover line) uses `SwapText`: the old
  words fully dissolve before the new ones rise in. A crossfade that showed both at once
  was rejected.
  Naming the craving weakens it. `UrgeReason` lists them in the person's own words:
  bored, drained, this is hard, anxious, alone, I need it.
- **Every answer closes it, except one.** Each craving gets a line on what would meet it
  better than the feed (a stretch, rest, a tiny step, writing it down, a real person),
  and the only button closes the tab. The person does the better thing themselves; the
  user explicitly didn't want in-app timers or forms for these.
- **"I need it" opens one site, never the block.** It appears only when the block has
  breaks on (`BreakPlan`, per block, 2 a day), asks what for, then offers 1 or 2 minutes.
  It spends a break (`BlockStore.spendBreak`) but the block stays on and keeps blocking
  everything else: only the chosen site is let through (`AppModel.allow`, keyed by
  `reachKey`). When the time is up Shift reads the screen again, and if you're still
  there the pause comes back. Only the lock decides when a block can be switched off.
  With no breaks left it shows, disabled, as "No breaks left today".
- **Never the same words twice in a row.** `PauseCopy` holds 48 pause headlines (by
  visit) and about 125 turning-back lines (general, harder, and per craving), dealt by
  `CopyDeck` so nothing repeats until the rest of its set has been seen. The user asked
  for this explicitly; add lines rather than trimming them, in the voice described there.
- **Reward turning back, immediately.** Flop's happy face, a sparkle burst and the `reward` chime. This is the step that
  builds the habit; before it, turning back got nothing.
- **Repeats cost more.** Reaches are counted per block and target for an hour
  (`reaches`, keyed by `reachKey`, not the process), so switching tabs or relaunching the
  browser can't reset anything. 10 s, then 20 s, then 30 s, with warmer copy each time.
- **No shame, anywhere.** The voice is a friend's. The urge is "the pull", not the person.
- **Plans in their own words.** The Dashboard's `WeekPanel` shows the week's reaches by
  craving and peak hour, and takes an if-then plan per craving. The pause shows the plan
  back on that craving's screen. Everything is in `UrgeLog`, on disk, local only.
- `Close it` closes the **tab** (Command-W posted to the browser's pid by `TabCloser`, after
  yielding activation to it). Apps are asked to quit.

`NudgeHUDController` now serves three kinds: `hint` (soft drift), `reward` (happy Flop,
after the pause closes), and `status` (break started, no breaks left). `hideHint()` takes down only hints, so a
reward survives the app switch it usually lands on.

The standalone semantic classifier and text readers are outside the active detection path. `AppModel` applies explicit rules and handles confirmation and enforcement.

## Conventions

- Swift 5 language mode, SwiftUI plus AppKit where needed, `@Observable`, macOS 26 APIs are fine.
- **Not sandboxed**, Hardened Runtime on. Distribution: Developer ID plus notarization (no Mac App Store).
- The Xcode project uses **folder-synced groups** (`PBXFileSystemSynchronizedRootGroup`): new files in `Shift/` are picked up automatically, so don't hand-edit file references into `project.pbxproj`.
- Keep the UI native and calm; the pause is the only full-screen surface.
- Small, focused commits on `main`, pushed to `origin`.
- Every verdict carries a human-readable reason naming which tier decided. Nothing shows
  it live any more: the popover's panel is gone, so reasons surface only in the log.

## Roadmap (PRD §16)

- **M0 Skeleton:** done. Builds clean, runs, shield preview wired.
- **M1 Strict MVP:** done in code, **not yet verified by hand**. Reworked in v0.3 around blocks: main window, block editor, per-block schedules, locks and breaks, launch at login, headless watchdog, quit and Trash protection, onboarding, nudge HUD, settings, screen-text reading.
- **M2 AI v1:** dropped on 23 Nov 2026. The user removed focus goals and intent checks;
  the PRD's AI sections are out of date on this point.
- **M3 Beta:** Network Extension hostname backstop (verify the non-MDM approval path first), weekly insights, Sparkle, notarized beta.
- **M4 AI v2:** VLM tier (and the downloader it needs), doomscroll detection, on-device adapter from evaluation feedback.
