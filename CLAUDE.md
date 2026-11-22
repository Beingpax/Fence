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
  watchdog pair, quit and Trash protection, real ScreenCaptureKit and Vision text reading.
- Not built: the intent tiers. There is still no AI. `Block.goal` is captured and shown
  but nothing judges against it yet.
- **The binary has two entry points.** `Shift` is the app; `Shift --watchdog` is the
  headless watchdog. `main.swift` branches, which is why `ShiftApp` has no `@main`.

## Build and run

```bash
xcodebuild -project Shift.xcodeproj -scheme Shift -configuration Debug -destination 'platform=macOS' build
```

- Run from Xcode with Cmd+R. Shift is an `LSUIElement` menu bar app (◎ icon), with no Dock icon.
- Test the shield without side effects: menu bar → *Preview shield* → Strike 1/2/3.
- Real test: start a Firm session, open `instagram.com` or `youtube.com/shorts` in Safari or Chrome. The shield should appear in about 2–3 seconds.
- Permissions: Accessibility (titles, page text, URLs) and, later, Screen Recording (OCR) and Automation per browser (close tab).
- **Signing is load-bearing for permissions.** `DEVELOPMENT_TEAM = V6J6A3VWY2` is set on both configurations, so builds are signed with a real identity. Do not let this fall back to ad-hoc. macOS keys TCC grants to the designated requirement, and an ad-hoc signature puts the binary's `cdhash` in that requirement, so **every rebuild silently voids the Accessibility grant** and the app reports "not granted" while System Settings still shows it enabled. Verify with `codesign -d -r- <app>`: the requirement must name the certificate, not a `cdhash`. If a grant ever does go stale, `tccutil reset Accessibility com.beingpax.Shift` and grant it again.
- Automated GUI testing needs Accessibility and Screen Recording granted to the terminal running Claude Code. Without them, `osascript` UI scripting fails with -1719 and `screencapture` fails outright, so shield verification has to be manual.

## Verification checklist (not yet walked through by hand)

1. **Menu bar.** Icon appears; the count next to it matches the number of active blocks.
2. **Main window.** Menu bar → Open Shift. Create a block, add sites and apps, save.
3. **Blocking.** Switch the block on, visit a listed site in Safari and Chrome. The shield
   should appear within about 3 s and close the tab, not the browser.
4. **Schedules.** Set a window that starts a minute from now and confirm it self-activates.
5. **On-screen words.** Add a keyword, grant Screen Recording, and confirm it fires on a
   page whose address says nothing. Confirm capture stays off when no block has keywords.
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

- a **list**: websites, paths, apps, on-screen keywords, and exceptions that always win,
  in either `blocklist` or `allowlist` mode;
- a **schedule**: `.always`, `.scheduled([ScheduleWindow])`, or `.manual(minutes:)`;
- a **lock**: `none`, `duration`, `untilTime`, `randomString`, or `restart`, which engages
  the moment the block is switched on;
- **breaks**: optional, length and per-day allowance fixed in advance;
- **friction**: how hard the shield pushes back, independent of the lock.

Several blocks can be active at once. `BlockEvaluator` asks each active block in order and
the first with an opinion wins. A block is active when it is enabled or locked on, is
inside its schedule, and is not on a break.

Rules that are easy to get wrong, and are covered by the tests:

- Schedule windows may run past midnight; the window belongs to the day it started on.
- An `untilTime` lock set to a time already past today rolls to tomorrow.
- A `restart` lock is released by comparing boot time, not app lifetime.
- While locked, a block may be edited only to become stricter. Entries can be added,
  exceptions can only be removed, and schedule, mode and lock method are frozen.
- `Finder`, System Settings and Shift itself are never blocked, so a bad allow-list can't
  lock someone out of fixing it.

## Threading rules

`SWIFT_STRICT_CONCURRENCY = complete` is on. Keep the build warning-free under it.

- `AppModel`, `BlockStore` and the window controllers are `@MainActor`. SwiftUI reads them.
- Anything that talks to another process runs off the main actor and is awaited:
  Accessibility reads (`WindowInspector`, 0.5 s messaging timeout), Apple Events
  (`AppleScriptRunner`, one serial queue plus a 1.5 s deadline), and screen capture
  (`ScreenTextReader`, an actor).
- `ContextMonitor` drops overlapping samples rather than queueing them, so a slow reading
  can't build a backlog behind it.
- Block writes are debounced and encoded off the main actor. `saveNow()` is for the cases
  where losing the write would hand the user a way out.

## Product decisions (don't relitigate without asking)

- **Blocks come from templates.** `BlockTemplate.all` is the gallery people start from.
  A blank block is one of the options, not the only one.
- **The app picker is in-app.** `InstalledApps` scans the application folders once, off the
  main actor, and caches icons. Don't send people to an open panel.
- **No allow-list mode and no on-screen keyword rules.** Both were cut as clutter. A block
  blocks what's listed, with exceptions that always win.
- **One window.** Settings is a section of the main window, not a `Settings` scene, so a
  menu bar app never puts two windows on screen. `MainSection` drives the sidebar, the
  model owns the selection, and Cmd+, opens the window at Settings. Don't reintroduce
  `SettingsLink`; it needs a `Settings` scene and there isn't one.
- **Blocks, not sessions.** A timer can't express "never Instagram" or "no games on
  weeknights". The old `FocusSession`, `BlockRules` and `Strictness` types are gone.
- **Locking and friction are different things.** The lock decides whether the switch works.
  Friction decides what the shield does when you hit it. Don't merge them.
- **The app icon is generated, not drawn by hand.** `Tools/make-icon.swift` renders every size and rewrites the appiconset's `Contents.json`. Edit the script, not the PNGs.

- **Name:** "Shift", subtitle "Local AI App & Website Blocker".
- **No Dock icon by default,** but there is a "Show Shift in the Dock" switch in Settings → General that flips the activation policy at runtime. `LSUIElement` keeps the default as menu-bar-only.
- **Platform:** Mac only, Apple Silicon, **macOS 26+** (raised from 14 in v0.2). The floor exists so Apple's Foundation Models can be assumed present, with no `#available` forks in the AI path.
- **Everything is local.** Never send screen content, OCR text, accessibility text or URLs off the device. No cloud fallback, not even optional.
- **Nothing to download.** The model tier is Apple's built-in Foundation Models, not a 300 MB MLX classifier. This deleted the model downloader, the CDN, the signed manifest and version management from scope. A downloader only returns in M4 for the optional VLM tier.
- **Detection is a cheap-first cascade:** rules → page text → embeddings → Foundation Models → VLM (M4, on demand). Rules must work with no model at all.
- **Screen capture is currently idle.** `ScreenTextReader` is built and correct, but the
  keyword rules that consumed it were cut, so `ContextMonitor.wantsScreenText` stays false.
  The intent tier is its next consumer. Don't switch it on without one.
- **Screen capture only runs when a rule needs it.** The engine sets `ContextMonitor.wantsScreenText` only when an active block has keywords and Screen Recording is granted. A perceptual-hash gate then skips recognition when the screen hasn't changed. Never put capture on a timer.
- **Two text channels, compared not assumed.** Tier 1a is page text from the accessibility tree (exact strings, no Screen Recording permission, nearly free). Tier 1b is ScreenCaptureKit + Vision OCR (covers canvas, video, games, hostile apps). Both get built in M2 and compared on real usage against the gates in PRD §8.3 before either becomes the default. Expect AX to win in browsers and OCR to win everywhere else, but prove it.
- **Read URLs from the accessibility tree**, not Apple Events. That removes the per-browser Automation prompt from onboarding. Apple Events stay only for *closing* a tab.
- **A Foundation Models guardrail violation counts as evidence for a block**, never as a failure and never as an allow. The content that trips Apple's safety filter is the content a blocker exists to catch. Say so honestly in the reason line.
- **Intent over domains:** judge the screen against the session's goal. Path-aware rules (`youtube.com/shorts` blocked, `youtube.com` allowed).
- **Shield:** frosted full-screen window on every display and Space; while it's up, the Dock, menu bar and Cmd+Tab are disabled. The text says "Not now." plus a one-line reason.
  - Browsers: **close the tab, never quit the browser.** Native apps: force quit.
  - **Escalation:** Firm = strike 1 immediate, strike 2 a 15 s countdown, strike 3+ 15 s plus typing *"I am choosing to get distracted"*. Locked = 10 s / 30 s / 30 s plus the phrase. Gentle = always immediate.
  - **"Wrong call"** only unlocks after the countdown (it must not be an escape hatch). It allows that host or app for the session.
  - Only confident blocks show the shield; nudges never do. Default to allow on work apps when unsure.
- **Locked mode:** you can't end the session or quit Shift early.
- **Honesty:** an admin can always win. We sell friction, not a prison.

## Hard platform limits (researched, don't rediscover)

- **Screen Time frameworks do not exist on macOS.** FamilyControls, ManagedSettings and DeviceActivity are iOS and iPadOS only. There is no OS-level app shield to borrow, which is exactly why enforcement is app-level plus a watchdog, and why the honesty clause exists.
- **Socket-level network filtering is hostname-only.** HTTPS hides the path, so a `NEFilterDataProvider` can never do path-aware blocking. It is an M3 backstop, not a detection tier.
- **The macOS 26 full-URL filter is unusable for us.** It requires a Bloom filter plus a Private Information Retrieval *server* plus a dedicated entitlement. A server contradicts the local-only rule. Rejected, documented in PRD §10.2.
- **Foundation Models context is about 4,096 tokens** covering instructions, prompt, output and tool definitions together. Trim page text to roughly 2,500 tokens. Never send a whole page.
- **Chromium and Electron build accessibility trees lazily.** Chrome needs `AXEnhancedUserInterface` set on its application element; Electron needs `AXManualAccessibility`. Confirm success by reading the attribute back, because Chrome returns not-implemented even when it worked, and retry after about 150 ms because the tree fills asynchronously.
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
│                   Friction, BlockTint), BlockStore (persistence, locking, CRUD),
│                   ScreenContext, Verdict, ActivityEvent, DistractionPreset
├── Detection/      ContextMonitor (async sampling), WindowInspector (AX),
│                   Browser + AppleScriptRunner (off-main Apple Events),
│                   ScreenTextReader (ScreenCaptureKit + Vision, an actor)
├── Intelligence/   BlockEvaluator (tier 0), Hysteresis
├── Enforcement/    ShieldController, ShieldView, ShieldPolicy, GuardState,
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
blocks → `Hysteresis` (2 consistent readings) → `ShieldController.present` → resolve
(close tab / quit app / wrong call / take a break).

`DistractionClassifier` and `ScreenTextReading` are the seams for every new tier. Adding a tier should not touch `AppModel`.

## Conventions

- Swift 5 language mode, SwiftUI plus AppKit where needed, `@Observable`, macOS 26 APIs are fine.
- **Not sandboxed**, Hardened Runtime on, entitlement `com.apple.security.automation.apple-events`. Distribution: Developer ID plus notarization (no Mac App Store).
- The Xcode project uses **folder-synced groups** (`PBXFileSystemSynchronizedRootGroup`): new files in `Shift/` are picked up automatically, so don't hand-edit file references into `project.pbxproj`.
- Keep the UI native and calm; the shield is the only loud surface.
- Small, focused commits on `main`, pushed to `origin`.
- Every verdict carries a human-readable reason, and "What Shift saw" should name which tier decided.

## Roadmap (PRD §16)

- **M0 Skeleton:** done. Builds clean, runs, shield preview wired.
- **M1 Strict MVP:** done in code, **not yet verified by hand**. Reworked in v0.3 around blocks: main window, block editor, per-block schedules, locks and breaks, launch at login, headless watchdog, quit and Trash protection, onboarding, nudge HUD, settings, screen-text reading.
- **M2 AI v1:** `ScreenTextReader` is built (tier 1b). Still to do: `AXTextReader` (tier 1a) and the bake-off in PRD §8.3, `EmbeddingMatcher`, `FoundationModelJudge` with guided generation judging `Block.goal`, rabbit-hole detection.
- **M3 Beta:** Network Extension hostname backstop (verify the non-MDM approval path first), weekly insights, Sparkle, notarized beta.
- **M4 AI v2:** VLM tier (and the downloader it needs), doomscroll detection, on-device adapter from "wrong call" feedback.
