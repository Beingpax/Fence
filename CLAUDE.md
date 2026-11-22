# Shift: context for Claude

Shift is a **macOS-only, local-AI app and website blocker**: Cold Turkey-level strictness, but it understands what's on screen. Read `PRD.md` for the full spec; this file is the working memory of decisions already made.

Local folder: `~/Shift Focus`. Repo: https://github.com/Beingpax/Shift-Focus (branch `main`). Owner: Prakash Joshi Pax (`Beingpax`).

## Current status (read first)

- **M1 is written and compiles clean** (zero errors, zero warnings), but it has **not been run or verified yet**. Runtime verification is the first job in the next session: see "M1 verification checklist" below.
- **PRD is at v0.2** after a competitive and technical research pass. §18 of the PRD lists every change from v0.1.
- **Next after verification is M2**, the AI tiers. Nothing in the AI path has been written yet.
- Built and wired: menu bar app with live countdown, focus sessions, context monitor, rule-based classifier, hysteresis, full-screen shield with escalation, nudge HUD, five-step onboarding, launch at login, watchdog pair, quit and uninstall protection, four settings tabs.
- Stubs only: `ScreenTextReader` (OCR) and `LocalIntentModel` (the model tier, to be replaced by a Foundation Models judge).
- **Deployment target is 26.0** in `project.pbxproj`.
- **The binary has two entry points.** `Shift` is the app; `Shift --watchdog` is the headless watchdog. `main.swift` does the branching, which is why `ShiftApp` no longer carries `@main`.

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

## M1 verification checklist (nothing here has been run yet)

1. **Menu bar.** Icon appears; a running session shows minutes left next to it.
2. **Onboarding.** Delete `Shift.hasCompletedOnboarding.v1` from defaults to replay first run:
   `defaults delete com.beingpax.Shift Shift.hasCompletedOnboarding.v1`
3. **Preview shield** strikes 1–3, and **Settings → General → Show a nudge** for the HUD.
4. **Nudge HUD** must never take keyboard focus. Type in another app while it's up.
5. **Launch at login.** Toggle in Settings → General, then confirm in System Settings → General → Login Items.
6. **Watchdog.** Start a Locked session, then `pkill -f 'Shift.app/Contents/MacOS/Shift$'`. Shift should come back within ~5 s. Inspect with
   `launchctl print gui/$UID/com.beingpax.Shift.watchdog` and `log stream --predicate 'subsystem == "com.beingpax.Shift"'`.
7. **Quit protection.** Cmd+Q during a Locked session should show the "session is locked" alert. `kill -15` should be ignored; `kill -9` is expected to win.
8. **Trash protection.** Move Shift.app to the Trash during a Locked session; the watchdog should put it back.
9. **Clock hardening.** Winding the system clock forward should not end a session early.
10. **Clean up after testing:** `launchctl bootout gui/$UID/com.beingpax.Shift.watchdog`, delete
    `~/Library/LaunchAgents/com.beingpax.Shift.watchdog.plist`, and remove `~/Library/Application Support/Shift/guard.json`.

## Product decisions (don't relitigate without asking)

- **The app icon is generated, not drawn by hand.** `Tools/make-icon.swift` renders every size and rewrites the appiconset's `Contents.json`. Edit the script, not the PNGs.

- **Name:** "Shift", subtitle "Local AI App & Website Blocker".
- **No Dock icon by default,** but there is a "Show Shift in the Dock" switch in Settings → General that flips the activation policy at runtime. `LSUIElement` keeps the default as menu-bar-only.
- **Platform:** Mac only, Apple Silicon, **macOS 26+** (raised from 14 in v0.2). The floor exists so Apple's Foundation Models can be assumed present, with no `#available` forks in the AI path.
- **Everything is local.** Never send screen content, OCR text, accessibility text or URLs off the device. No cloud fallback, not even optional.
- **Nothing to download.** The model tier is Apple's built-in Foundation Models, not a 300 MB MLX classifier. This deleted the model downloader, the CDN, the signed manifest and version management from scope. A downloader only returns in M4 for the optional VLM tier.
- **Detection is a cheap-first cascade:** rules → page text → embeddings → Foundation Models → VLM (M4, on demand). Rules must work with no model at all.
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
│                   AppDelegate (quit protection), AppModel (@Observable, @MainActor orchestrator)
├── Models/         FocusSession, Strictness, ScreenContext, Verdict, BlockRules,
│                   ActivityEvent, DistractionPreset (onboarding answers → rules)
├── Detection/      ContextMonitor, WindowInspector (AX), Browser (close tab),
│                   AXTextReader (tier 1a, to build), ScreenTextReader (tier 1b, stub)
├── Intelligence/   DistractionClassifier, CascadeClassifier, RuleBasedClassifier,
│                   EmbeddingMatcher (tier 2, to build), FoundationModelJudge (tier 3, to build), Hysteresis
├── Enforcement/    ShieldController (NSWindow at .screenSaver + presentationOptions), ShieldView,
│                   ShieldPolicy, GuardState (UI ↔ watchdog handshake), LaunchAtLogin,
│                   WatchdogService (installs the agent), WatchdogRunner (the agent itself)
└── UI/             DesignSystem (Theme + glass surfaces), MenuBarView, SettingsView,
                    NudgeHUD, PermissionsManager, Onboarding/
```

### Where glass belongs
Liquid Glass goes on surfaces that float over *content*: the shield's controls, the
onboarding preset chips, the permission cards. It does **not** go inside the menu bar
popover, which is already a vibrant material, because glass on glass reads as washed out
and Apple warns against it. Standard bordered controls are correct there. The shield and
the nudge HUD use `BehindWindowBlur` rather than glass, because they float over *other
apps* and must sample the desktop.

### Design system
All spacing, radii, verdict colours and glass surfaces come from `Theme` and `glassCard()` in
`UI/DesignSystem.swift`. Two rules there are not optional: every glass surface falls back to an
opaque material under Reduce Transparency, and every animation falls back to a cross-fade under
Reduce Motion. The shield and the nudge HUD use `BehindWindowBlur` rather than Liquid Glass,
because both float over *other apps* and so must sample the desktop, which only
`NSVisualEffectView` does.

Flow: `ContextMonitor` sample → `AppModel.handle` → `CascadeClassifier` → `Hysteresis` (2 consistent readings) → `ShieldController.present` → resolve (close tab / force quit / wrong call).

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
- **M1 Strict MVP:** written, compiles clean, **not yet verified at runtime**. Launch at login (`SMAppService`), headless watchdog as a keep-alive launch agent, quit and Trash protection during Locked, monotonic clock hardening, five-step onboarding, nudge HUD, four settings tabs, Liquid Glass design pass.
- **M2 AI v1:** `AXTextReader` and `ScreenTextReader` both built, instrumented and compared per PRD §8.3; `EmbeddingMatcher`; `FoundationModelJudge` with guided generation; rabbit-hole detection.
- **M3 Beta:** Network Extension hostname backstop (verify the non-MDM approval path first), weekly insights, Sparkle, notarized beta.
- **M4 AI v2:** VLM tier (and the downloader it needs), doomscroll detection, on-device adapter from "wrong call" feedback.
