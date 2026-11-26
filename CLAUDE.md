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
- **Onboarding was redesigned on 25 Nov 2026** to be cleaner and more playful, with no
  stock controls: everything in `UI/Onboarding/OnboardingView.swift` is drawn by hand
  (progress pebbles, coral step labels, tap-to-pick tiles with a popping check,
  capsule fields, ink tag pills, permission cards, a twinkling pause preview, lock tiles,
  app chips, a custom switch, bouncing loading dots, squishy buttons). The window is
  880×720 with floating Back/Continue buttons and no footer bar. Each lock option shows
  its own settings under the tiles (duration chips, a time chooser with quick picks, the
  typing-challenge length), and they are saved into the new block. The mascot peeks over the
  welcome card (calm) and over the name card on the last step (happy). Pages slide in the
  direction of travel. Permission wording comes from `BlockingPermissionRow.feedback`, so
  onboarding and Settings never disagree. Not yet built or seen running.
- **Settings follows macOS's own settings layout** (rebuilt 26 Nov 2026, after the user
  found the playful version badly spaced). Titled groups (General, Nudges, Previews, How
  blocking works, Setup) of rows on white rounded cards with inset hairline dividers;
  13 pt text, rows about 38 pt tall, mini system switches, small push buttons; spacing in
  `SettingsMetrics` (groups 22 apart, title to card 7, rows 12 by 9). No mascot.
  **Permissions appear only while one still needs doing**, in a "Needs your attention"
  group at the top; allowed ones aren't listed at all. Explanations are hover tooltips.
  The shared playful pieces (`PlayType`, `paperCard`, `MascotCard`, `PaperSwitch`,
  `SquishButtonStyle`, `PillButtonStyle`, `PlayRhythm`, `RowDivider`, `PermissionLine`,
  `FloatingButtonStyle`) live in `UI/Design/Playful.swift`.
- **The Dashboard is "your day"** (26 Nov 2026; the user rejected the earlier greeting
  and stat-card version and asked for a different idea, not a restyle). Every block is
  a lane on a midnight-to-midnight ribbon: coral outline where it will guard you, faded
  once done, dashed while switched off, solid coral while on now. **The mascot sits on the
  ribbon at the current time**, peeking over the card's top edge and holding on, and
  moves along through the day with a coral "now" line falling from its hands. A speech
  bubble beside it says one sentence about right now, on whichever side has room.
  Above: the date in coral small caps and a greeting (the user loves this header), and
  "New block". No "Preview a pause" button here: the user removed it. Below: fact pills
  (times paused, last pause, next start) and the legend. Missing permissions sit in a card
  above the ribbon, and the mascot turns curious. `DayPlan` works out today's spans
  (overnight windows split across days). Redraws once a minute (`TimelineView(.everyMinute)`).
  The user has seen it running and loves it.
- **The Blocks page is one calm list** (26 Nov 2026, `UI/Main/BlocksView.swift`). Same
  header voice as the Dashboard (coral small caps such as "1 OF 3 ON RIGHT NOW", then
  "Your blocks", New block). Every block is a row in a single paper card, **in the user's
  own order so rows never jump when toggled**: icon (coral while on), name with a lock
  glyph if locked, a status ("On until 5:00 PM" in mint, "Starts
  9:00 PM", "Tomorrow 9:00 AM", "Off", a coral lock line) and the switch. **Timed blocks
  get a Start menu (25/50/90 min) instead of a switch.** Click a row to edit; right-click
  for Edit, timed runs and Delete. A card grid with sticker stacks and week strips came
  first and was rejected the same day as busy and glitchy to scroll, so keep this page
  free of lazy grids, entrance or looping animations and hover scaling; only each row's
  status follows the clock. **Rows hold only the main things**: no list of apps and
  sites, no schedule line and no hint text (the user asked; the editor has the details).
  Not yet built or seen running.
- **The sidebar is Shift's own and stays exactly as on `main`** (26 Nov 2026, the user's
  call after it was changed twice): a Liquid Glass panel (`.glassEffect(.regular)`) pinned to
  the window's leading edge, full height, with only its trailing corners rounded; the
  selected row uses `unemphasizedSelectedContentBackgroundColor`; section tiles are system
  orange, indigo and gray; the count badge is the accent colour. It is an exception to the
  palette rules. Don't flatten it to cream, swap it for `NSVisualEffectView` materials, or
  float it inset like the system sidebar.
- **The block editor keeps its `main` look; only its buttons float** (26 Nov 2026, the
  user's call). The sliding panel is the original glass (tinted 28% window background,
  pinned to the trailing edge, leading corners rounded), the editor sits on the `.sidebar`
  material, and its cards use the original frosted glass with a whisper of the block's
  colour: `GlassSurface` switches to that look when `\.usesGlassCards` is set, which only the
  editor does. Save and Unlock float as `FloatingButtonStyle(compact: true)` capsules with
  no footer bar: the same size as `main`'s buttons (13 pt semibold, 14 by 8 padding,
  text only), not onboarding's larger Continue.
- **No description lines under titles** in Settings and the Dashboard (26 Nov 2026, the
  user's call). Rows, sections and tiles show their title only; any explanation moves to a
  hover tooltip (`.help`). Exceptions: a permission that still needs fixing keeps its one
  instruction line; the How blocking works steps are the content itself; the Dashboard's
  live status line under the greeting stays. Onboarding keeps its subtitles; it's a
  guided first run.
- **The block editor's Save floats** over the panel as the same capsule as onboarding's
  Continue (`FloatingButtonStyle`, in `UI/Design/Playful.swift`), with no footer bar. Shared page pieces (`PlayHero`, `PlaySection`, `PlayRhythm`,
  `RowDivider`, `SwitchLine`, `ActionLine`, `PermissionLine`, `SoftPillButtonStyle`) are in
  `UI/Design/Playful.swift`. Not yet built or seen running.
- **The nudge mascot is new** as of 25 Nov 2026 (see "The mascot" under product
  decisions). The card moved to the bottom right. Not yet watched in the running app.
- Built: main window (Dashboard, Blocks, Activity), block editor, menu bar popover,
  the full-screen pause with time-of-day wallpapers, reward and hint HUD, onboarding, launch at login,
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
   reward. "I need it" appears only when the block allows breaks. Type a reason, pick 2 or
   5 minutes, and wait one minute for access to the matched rule. The close button
   cancels the wait. A third reach within an hour waits 30 s and plays
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
- **Breaks** are optional, with two starts per local day. Each gives 2 or 5 minutes of access after a one-minute wait.

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
- **The popover never shows warnings** (25 Nov 2026, at the user's request). Permission
  problems such as browser access appear only in the main window: the Dashboard and
  Settings. Don't put a warning, banner or "Review…" row back in the popover.
- **Launch always puts a window on screen**: setup on first launch, the main window after
  it (`AppModel.openApp`). `presentForUser` calls `orderFrontRegardless()` because
  `NSApp.activate()` is cooperative and lost to whatever app was in front.
- **Closing the main window frees it** (25 Nov 2026, at the user's request).
  `MainWindowController` drops the window and its view tree on close and builds a fresh
  one on the next open, keeping the last frame for the session. An unsaved inspector edit
  is lost on close; `newBlock` and `unlockTarget` are cleared with it.
- **Views read `BlockStore.activeBlockIDs`, not `block.isActive()`.** A schedule opening
  or closing edits nothing, so views reading only `blocks` stayed stale (the menu bar count
  among them). The set is refreshed on every change and every engine tick. The engine
  still uses `activeBlocks`, which asks the clock directly.
- **Blocks, not sessions.** A timer can't express "never Instagram" or "no games on
  weeknights". The old `FocusSession`, `BlockRules` and `Strictness` types are gone.
- **Locking and friction are different things.** The lock decides whether the switch works.
  Friction decides what the pause does when you hit it. Don't merge them.
- **The app icon is generated, not drawn by hand.** `Tools/make-icon.swift` renders every size and rewrites the appiconset's `Contents.json`. Edit the script, not the PNGs.
- **The mascot replaced Flop on 25 Nov 2026.** It is the "Classic" creature from the HTML
  studies (`Studies/mascot-compare.html`): a marigold (`#ffad33`) soft-rectangle body with round
  ears, an ink outline, white mitten hands and an antenna. `UI/MascotView.swift` draws it in one
  `Canvas`, no image assets. It has no name in the UI; copy says "Shift".
  - **Chosen over a glossy 3D direction.** The user compared both side by side (standing,
    peeking over the card, beside the card) and picked the flat cartoon. Don't swap it for
    shaded 3D or bring Flop back without asking.
  - **The antenna bulb carries the mood**, readable from the corner of the eye: warm at
    rest, teal when curious (the drift hint), bright when you turn back, amber when
    something failed. `MascotMood` has exactly the four moods the HUD uses: `calm`,
    `curious`, `happy`, `sorry`. The studies hold sixteen more; add one only when a real
    moment needs it.
  - **It peeks over the card and holds its edge.** The view draws twice: `.body` behind the
    card, clipped at the card's top edge so it can rise from behind glass without showing
    through, and `.hands` in front of it. Both layers share one `start` date so they move on
    one clock. The happy mood waves one hand; sorry shrugs with both.
  - **Motion is the original gentle idle**: breathing, a slow sway, jittered blinks with
    the odd double, quick glances that snap and hold. Two attempts at richer per-mood hand
    choreography (continuous oscillation, then keyframed beats) were rejected by the user
    as worse. Don't add gesture animation without asking.
  - The card sits **bottom right, above the Dock**, at the user's request. It slides in
    from beyond the right edge like a banner, then the mascot pops up from behind it and
    takes hold of the edge; it leaves the same way. Under Reduce Motion everything is a
    cross-fade and the mascot holds still.
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
    `CREDITS.md`. Files are **2560×1440 JPEG XL** (`cjxl -d 1.0 -e 9`, SSIMULACRA2
    ≥ 85.8, 7.6 MB for all 20; the 4K originals were 31.8 MB). The photos were generated and
    upscaled, so nothing real lives above 2560 px. Chosen on 26 Nov 2026 over JPEG (about 2×
    the size), AVIF (15–20% bigger) and HEIC/WebP (bigger and worse), and because ImageIO
    decodes JXL in about 30 ms cold against 110–150 ms for AVIF and HEIC; that decode delays
    the pause. Originals are in git history before that date. `PauseWallpaper` decodes each
    photo once, no larger than the biggest display needs. Green land, not desert: the user rejected dunes. A hand-rolled gradient
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
- **`SMAppService` reports a never-registered agent as `.notFound`, not `.notRegistered`.**
  Register on both, or the helper is never set up and the row reads "couldn't start".
- **`CGPreflightPostEventAccess` can stay false until relaunch** after the user grants
  Accessibility (macOS 27 calls the pane Device Control and Data Access). Posting events
  is granted by the same list, so `canPostKeyboardEvents` also accepts `AXIsProcessTrusted`.
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
│                   Urge (the reasons shown in the pause),
│                   PauseCopy (every line at the pause and on turning back, + CopyDeck)
├── Detection/      ContextMonitor (async sampling), AddressObserver (AX notifications),
│                   WindowInspector (AX),
│                   Browser (browser identities)
├── Intelligence/   BlockEvaluator (tier 0), Hysteresis
├── Enforcement/    PauseController + PauseView + PauseBackdrop (DayPeriod), TabCloser,
│                   NudgeSound, GuardState,
│                   LaunchAtLogin, WatchdogService, WatchdogRunner
└── UI/             DesignSystem (Theme, BlockBadge), Design/ (Materials, Controls),
                    MenuBarView, SettingsView (a pane, not a scene), NudgeHUD, MascotView,
                    PermissionsManager, Main/ (MainWindowController, MainWindowView +
                    MainSection, DashboardView, BlockEditorView + BlockInspector +
                    AppPickerView), Onboarding/
```

### The design language
Modelled on IINA: translucent chrome, depth from material weight rather than shadows, and
generous spacing. Three rules hold it together.

1. **"Sorbet": coral and mint on warm cream; marigold is the mascot's alone.** Chosen by
   the user on 25 Nov 2026 from `Studies/palette-compare.html` (five playful directions,
   three real screens each, beside the mascot), after rejecting paper/ink/marigold and then
   every calm muted option (pine, evergreen, lake, harbor) as not playful enough.
   **Coral** (`Paper.coral`, #F4573F light / #FF8574 dark, `Paper.onCoral` on top) is the
   main colour: primary buttons, selection, progress, tags, badges, focus rings.
   `Paper.coralText` is a deeper coral for small text like the step label. **Mint**
   (`Paper.mint`, #17A877 / #45D9A6) means done and nothing else: allowed permissions, the
   Active tag, the Dashboard's active dot. Neutrals carry the rest: cream background
   #FFF6EE, white cards, warm near-black text. Light-mode fills are a shade deeper than the
   study swatches so white text on them keeps its contrast. Rules the user set:
   - **Two colours, not a rainbow.** The study's rainbow icons and chunky buttons were
     options, not part of the choice.
   - **Marigold only on the mascot** (`MascotPalette`). Never on buttons, tiles or labels.
   - **No black fills** for buttons or tiles. Neutral tiles use `Paper.tile`.
   - **The system accent colour only on switches** and pick controls.
   - A finished permission shows a mint check tile; **no "Done" badge** beside it.
   - No tinted washes behind whole cards, no gradients, no indigo or violet.
   **Dark mode:** shadows don't read on dark paper, so depth comes from a wider
   background-to-card step and a stronger hairline (white 13% vs black 9%). Anything with
   its own dark fill (the pause preview) gets a light edge. Sidebar tiles always draw a
   white icon, so the Dashboard tile uses the light-mode coral in both modes.
2. **Controls are Shift's own**, in `UI/Design/Controls.swift`: `SegmentedSelector`,
   `ShiftSwitch`, `OptionCard`, `TimeField`, `NumberStepper`, `DayPicker`, `Chip`,
   `ShiftTextField`, and the `shiftProminent` / `shiftSoft` button styles. Reach for these
   before a stock control, so the app reads as one thing.
3. **Structure comes from `Panel` and `PanelRow`**, not `Form`, except in onboarding and
   the Dashboard (playful paper cards from `UI/Design/Playful.swift`) and Settings
   (macOS-style grouped rows in `SettingsView.swift`).
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
→ `handlePause` → close the tab and reward the user, or start temporary access.

### The pause
Every choice here comes from habit research. Check changes against these, and don't
relitigate them without asking:

- **Catch the cue, before the reward.** `AddressObserver` subscribes to the front app's
  Accessibility notifications (focused element, title, window, `AXLoadComplete`), so
  pressing Return wakes a sample within ~0.1 s. Value-changed is deliberately *not*
  observed: it fires on every keystroke in every text field. A feed that never pays out
  stops being worth reaching for, which is why speed matters more than anything else.
- **Full screen, no mascot.** `PauseController` covers every display with `PauseBackdrop`
  and locks out the Dock, menu bar and Cmd+Tab. An earlier version covered only the
  browser window with Flop on a frosted panel; the user rejected it because the page
  stayed visible around it. The mascot appears only afterwards, in the reward card.
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
  non-sequitur. The question asks what prompted the reach. Each chip has a short label and
  a symbol, with a longer description on hover. Choosing a chip replaces the question with its
  answer. The solid white close button stays outside the panel throughout the pause. Return
  activates it outside the reason form. Sources: GOV.UK's
  one-thing-per-page, Hick's law, one sec's breath-then-choice.
- **Neutral glass and white action buttons.** The frosted panel has a dark wash for readability.
  The access choices and close action use white capsules with dark text. The feeling choices
  use translucent cards with white labels. Their icons use the same solid system-colour tiles as the sidebar's
  (`SidebarIconTile`, which now takes a `size`): yellow, indigo, orange, teal, pink, green.
  Tinted, semi-transparent circles were rejected. The user rejected fully
  colour-coded chips, white-only symbols, and the teal/orange/purple tints in Settings.
  Settings and Dashboard panels stay neutral.
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
  breaks on (`BreakPlan`, per block, 2 a day), asks what for, then offers 2 or 5 minutes
  of access after a one-minute wait. The countdown uses the same frosted panel and
  continuously draining bar as the pause. Closing the target during the wait cancels it.
  When access begins, it spends a break (`BlockStore.spendBreak`) and temporarily allows
  the matched rule (`AppModel.allow`, keyed by `reachKey`). When access expires, Shift
  reads the screen again and restores the pause if the current context is still blocked.
  With no breaks left it shows, disabled, as "No breaks left today".
- **Never the same words twice in a row.** `PauseCopy` holds 48 pause headlines (by
  visit) and about 125 turning-back lines (general, harder, and per craving), dealt by
  `CopyDeck` so nothing repeats until the rest of its set has been seen. The user asked
  for this explicitly; add lines rather than trimming them, in the voice described there.
- **Reward turning back, immediately.** The mascot's happy face, a sparkle burst and the `reward` chime. This is the step that
  builds the habit; before it, turning back got nothing.
- **Repeats cost more.** Reaches are counted per block and target for an hour
  (`reaches`, keyed by `reachKey`, not the process), so switching tabs or relaunching the
  browser can't reset anything. 10 s, then 20 s, then 30 s, with warmer copy each time.
- **No shame, anywhere.** The voice is a friend's. The urge is "the pull", not the person.
- `Close it` closes the **tab** (Command-W posted to the browser's pid by `TabCloser`, after
  yielding activation to it). Apps are asked to quit.

`NudgeHUDController` now serves three kinds: `hint` (soft drift), `reward` (happy mascot,
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
- **M3 Beta:** Network Extension hostname backstop (verify the non-MDM approval path first), Sparkle, notarized beta.
- **M4 AI v2:** VLM tier (and the downloader it needs), doomscroll detection, on-device adapter from evaluation feedback.
