# Shift: context for Claude

Shift is a **macOS-only, local-AI app and website blocker**: Cold Turkey-level strictness, but it understands what's on screen. Read `PRD.md` for the full spec; this file is the working memory of decisions already made.

Local folder: `~/Shift Focus`. Repo: https://github.com/Beingpax/Shift-Focus (branch `main`). Owner: Prakash Joshi Pax (`Beingpax`).

## Current status (read first)

- **The app is organised around blocks, not sessions** as of 22 Nov 2026. This replaced the
  original focus-session model. See "The block model" below; it is the most important
  thing to understand before changing anything.
- **Builds clean** with zero errors and zero warnings, including under
  `SWIFT_STRICT_CONCURRENCY = complete`, which is now switched on in the project.
- **Runtime verification is still thin.** The app launches and stays up, and the schedule
  and lock maths have standalone tests (`./Tools/run-block-tests.sh`, 22 assertions). The
  UI flows have not been walked through by hand.
- Built: main window (Dashboard, Blocks, Activity), block editor, menu bar popover,
  full-screen shield with escalation and breaks, nudge HUD, onboarding, launch at login,
  watchdog pair, and quit and Trash protection.
- Active detection uses app, website, and path rules. Optional nudges use window-title keywords.
- **The binary has two entry points.** `Shift` is the app; `Shift --watchdog` is the
  headless watchdog. `main.swift` branches, which is why `ShiftApp` has no `@main`.

## Build and run

```bash
xcodebuild -project Shift.xcodeproj -scheme Shift -configuration Debug -destination 'platform=macOS' build
```

- Run from Xcode with Cmd+R. Shift is an `LSUIElement` menu bar app (◎ icon), with no Dock icon.
- Test without side effects: Settings → Previews has each nudge rung, the shield, and the soft drift hint.
- Real test: switch on a block listing `instagram.com` or `youtube.com/shorts`, then open it in Safari or Chrome. The first nudge should lean in within about 3 seconds, and the shield about 15 seconds after that if you stay.
- Shift requests Accessibility for window titles and browser addresses.
- **Signing is load-bearing for permissions.** `DEVELOPMENT_TEAM = V6J6A3VWY2` is set on both configurations, so builds are signed with a real identity. Do not let this fall back to ad-hoc. macOS keys TCC grants to the designated requirement, and an ad-hoc signature puts the binary's `cdhash` in that requirement, so **every rebuild silently voids the Accessibility grant** and the app reports "not granted" while System Settings still shows it enabled. Verify with `codesign -d -r- <app>`: the requirement must name the certificate, not a `cdhash`. If a grant ever does go stale, `tccutil reset Accessibility com.beingpax.Shift` and grant it again.
- Automated GUI testing needs Accessibility and Screen Recording granted to the terminal running Claude Code. Without them, `osascript` UI scripting fails with -1719 and `screencapture` fails outright, so shield verification has to be manual.

## Verification checklist (not yet walked through by hand)

1. **Menu bar.** Icon appears; the count next to it matches the number of active blocks.
2. **Main window.** Menu bar → Open Shift. Create a block, add sites and apps, save.
3. **Blocking.** Switch the block on, visit a listed site in Safari and Chrome. A nudge
   should lean in from the right within about 3 s, then two more 5 s apart, then the
   shield. Leaving the site at any rung should end it silently. The shield's primary
   action quits the browser.
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
  Accessibility reads (`WindowInspector`, 0.5 s messaging timeout) and screen capture
  (`ScreenTextReader`, an actor).
- `ContextMonitor` drops overlapping samples rather than queueing them, so a slow reading
  can't build a backlog behind it.
- Block writes are debounced and encoded off the main actor. `saveNow()` is for the cases
  where losing the write would hand the user a way out.

## Product decisions (don't relitigate without asking)

- **Onboarding creates the first block** from the user's choices. Add Block opens a blank editor.
- **The app picker is in-app.** `InstalledApps` scans the application folders once, off the
  main actor, and caches icons. Don't send people to an open panel.
- **Explicit lists contain websites, paths and apps.** Only a matching rule can raise the shield.
- **One window.** Settings is a section of the main window, not a `Settings` scene, so a
  menu bar app never puts two windows on screen. `MainSection` drives the sidebar, the
  model owns the selection, and Cmd+, opens the window at Settings. Don't reintroduce
  `SettingsLink`; it needs a `Settings` scene and there isn't one.
- **Blocks, not sessions.** A timer can't express "never Instagram" or "no games on
  weeknights". The old `FocusSession`, `BlockRules` and `Strictness` types are gone.
- **Locking and friction are different things.** The lock decides whether the switch works.
  Friction decides what the shield does when you hit it. Don't merge them.
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
    want attention without taking it.

- **Name:** "Shift", subtitle "Local App & Website Blocker".
- **No Dock icon by default,** but there is a "Show Shift in the Dock" switch in Settings → General that flips the activation policy at runtime. `LSUIElement` keeps the default as menu-bar-only.
- **Platform:** Apple Silicon Macs running macOS 26 or later.
- **Detection stays local.** Read browser addresses through Accessibility. Match enabled app, website, and path rules before considering a title-based nudge.
- **Nudges come before the shield.** A rule match no longer raises the shield directly.
  `NudgeLadder` shows 3 nudges: each appears for 5 s, then **leaves the screen for 5 s**
  before the next. The pause is deliberate — three nudges back to back read as one long
  complaint, whereas appearing, leaving and returning reads as someone checking on you,
  and it leaves a quiet moment in which to actually close the tab. The last rung also
  clears before the shield lands. Leaving at any point ends it with nothing having
  happened. See "The nudge ladder" below.
- **Shield:** frosted full-screen window on every display and Space; while it's up, the Dock, menu bar and Cmd+Tab are disabled. The text says "Not now." plus a one-line reason.
  - **Quit the entire browser or app.** Let the user respond when the target shows a quit confirmation.
  - **One tier, not three.** The ladder is the escalation now, so the shield is always a
    10-second wait plus **20 words in your own hand** about what you were doing and what
    pulled you away. That replaced copying out a fixed sentence: transcribing "I am
    choosing to get distracted" is friction you can perform without reading it, and by
    the third time it is muscle memory. Sentences you have to compose cannot be performed
    absently, and they leave you with the answer. The old per-day
    Gentle/Firm/Severe strike tiers and `DailyStrikeCounts` are gone — friction that grew
    with a count the user couldn't see explained nothing.
  - **The backdrop is a photograph** (`ShieldDawn`), twilight over dunes, under the
    Unsplash License — see `CREDITS.md`. A hand-rolled gradient always looks hand-rolled
    at full-screen size, and this is the one surface that fills a display. It is also
    deliberately *not* an angry red: this appears after three nudges have already been
    ignored, so being louder adds nothing, and "start again" is the note to hit. Keep the
    scrim light — the sky already carries white type, and a heavy scrim wastes the photo.
  - **No progress indicator anywhere.** No "nudge 2 of 3" and no dots. A tally made the
    whole thing read as a machine keeping score; the character's ears and colour say
    where you are.
  - Only confident blocks reach the ladder; soft hints never do. Default to allow on work apps when unsure.
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
│                   ScreenContext, Verdict, ActivityEvent, DistractionPreset
├── Detection/      ContextMonitor (async sampling), WindowInspector (AX),
│                   Browser (browser identities),
│                   ScreenTextReader (ScreenCaptureKit + Vision, an actor)
├── Intelligence/   BlockEvaluator (tier 0), Hysteresis
├── Enforcement/    ShieldController, ShieldView, ShieldPolicy, GuardState, NudgeLadder,
│                   LaunchAtLogin, WatchdogService, WatchdogRunner
└── UI/             DesignSystem (Theme, BlockBadge), Design/ (Materials, Controls),
                    MenuBarView, SettingsView (a pane, not a scene), NudgeHUD,
                    PermissionsManager, Main/ (MainWindowController, MainWindowView +
                    MainSection, DashboardView, BlockEditorView + BlockInspector +
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

Liquid Glass button styles are still right on the shield, which floats over other apps.
The shield and the nudge HUD use `BehindWindowBlur` because they must sample the desktop.

### Design system
All spacing, radii, verdict colours and glass surfaces come from `Theme` and `glassCard()` in
`UI/DesignSystem.swift`. Two rules there are not optional: every glass surface falls back to an
opaque material under Reduce Transparency, and every animation falls back to a cross-fade under
Reduce Motion. The shield and the nudge HUD use `BehindWindowBlur` rather than Liquid Glass,
because both float over *other apps* and so must sample the desktop, which only
`NSVisualEffectView` does.

Flow: `AppModel.engineTick` (1 s) decides which blocks are active and starts or stops
detection → `ContextMonitor` sample → `AppModel.handle` → `BlockEvaluator` over the active
blocks → `Hysteresis` (2 consistent readings) → `NudgeLadder` (3 nudges, 5 s apart) →
`ShieldController.present` → resolve (quit app / take a break).

### The nudge ladder
`Enforcement/NudgeLadder.swift` owns the escalation between "you matched a rule" and "your
screen is covered". Three rules there are easy to get wrong:

- **It is keyed on the rule and the process, not `context.signature`.** A page's title
  churns while the user sits still, and a signature key would restart the ladder on every
  churn, so it would never reach the shield.
- **Timing is driven by the ladder, not the 1.5 s sampler**, so the rungs land on exact
  5-second intervals. Presence stays authoritative: `isStillHere` re-evaluates the rules
  immediately before every rung, and `AppModel.endLadder()` tears the ladder down the
  moment a sample stops matching.
- **`showNudges` does not gate it.** That preference is for the soft intent and
  feed-keyword hints. The ladder is how blocking works, so it always runs.

`NudgeHUDController` serves both: `hint(reason:detail:)` for the soft kind (fades after
5 s, no progress dots) and `ladder(step:headline:detail:)` for the rungs. A rung replaces
the one before it, which is why `show` has to cancel an in-flight fade-out.

The standalone semantic classifier and text readers are outside the active detection path. `AppModel` applies explicit rules and handles confirmation and enforcement.

## Conventions

- Swift 5 language mode, SwiftUI plus AppKit where needed, `@Observable`, macOS 26 APIs are fine.
- **Not sandboxed**, Hardened Runtime on. Distribution: Developer ID plus notarization (no Mac App Store).
- The Xcode project uses **folder-synced groups** (`PBXFileSystemSynchronizedRootGroup`): new files in `Shift/` are picked up automatically, so don't hand-edit file references into `project.pbxproj`.
- Keep the UI native and calm; the shield is the only loud surface.
- Small, focused commits on `main`, pushed to `origin`.
- Every verdict carries a human-readable reason, and "What Shift saw" should name which tier decided.

## Roadmap (PRD §16)

- **M0 Skeleton:** done. Builds clean, runs, shield preview wired.
- **M1 Strict MVP:** done in code, **not yet verified by hand**. Reworked in v0.3 around blocks: main window, block editor, per-block schedules, locks and breaks, launch at login, headless watchdog, quit and Trash protection, onboarding, nudge HUD, settings, screen-text reading.
- **M2 AI v1:** Accessibility and OCR are wired into `IntentClassifier` for active
  blocks with a goal. Still to do: the bake-off in PRD §8.3, semantic calibration,
  automatic screen changes without interaction, and rabbit-hole detection.
- **M3 Beta:** Network Extension hostname backstop (verify the non-MDM approval path first), weekly insights, Sparkle, notarized beta.
- **M4 AI v2:** VLM tier (and the downloader it needs), doomscroll detection, on-device adapter from evaluation feedback.
