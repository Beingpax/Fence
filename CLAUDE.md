# Shift: context for Claude

Shift is a **macOS-only, local-AI app and website blocker**: Cold Turkey-level strictness, but it understands what's on screen. Read `PRD.md` for the full spec; this file is the working memory of decisions already made.

Local folder: `~/Shift Focus`. Repo: https://github.com/Beingpax/Shift-Focus (branch `main`). Owner: Prakash Joshi Pax (`Beingpax`).

## Current status (read first)

- **The skeleton builds clean** as of 22 Nov 2026: zero errors, zero Swift warnings, and it launches and runs as a menu bar process. No source changes were needed.
- **PRD is at v0.2** after a competitive and technical research pass. §18 of the PRD lists every change from v0.1. Three decisions were reversed; see "Product decisions" below.
- **Next up is M1**, not M2. Nothing in the AI path has been written yet.
- Built and wired: menu bar app, focus sessions, context monitor (frontmost app, AX window title, browser URL via AppleScript), rule-based classifier, hysteresis, full-screen shield with escalation, settings tabs.
- Stubs only: `ScreenTextReader` (OCR) and `LocalIntentModel` (the model tier, now to be replaced by a Foundation Models judge).
- **Deployment target is now 26.0** in `project.pbxproj`, and the project still builds clean after the bump.

## Build and run

```bash
xcodebuild -project Shift.xcodeproj -scheme Shift -configuration Debug -destination 'platform=macOS' build
```

- Run from Xcode with Cmd+R. Shift is an `LSUIElement` menu bar app (◎ icon), with no Dock icon.
- Test the shield without side effects: menu bar → *Preview shield* → Strike 1/2/3.
- Real test: start a Firm session, open `instagram.com` or `youtube.com/shorts` in Safari or Chrome. The shield should appear in about 2–3 seconds.
- Permissions: Accessibility (titles, page text, URLs) and, later, Screen Recording (OCR) and Automation per browser (close tab). They're tied to the code signature, so re-grant after signing changes.
- Automated GUI testing needs Accessibility and Screen Recording granted to the terminal running Claude Code. Without them, `osascript` UI scripting fails with -1719 and `screencapture` fails outright, so shield verification has to be manual.

## Product decisions (don't relitigate without asking)

- **Name:** "Shift", subtitle "Local AI App & Website Blocker".
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
├── App/            ShiftApp (MenuBarExtra + Settings), AppModel (@Observable, @MainActor orchestrator)
├── Models/         FocusSession, Strictness, ScreenContext, Verdict, BlockRules, ActivityEvent
├── Detection/      ContextMonitor, WindowInspector (AX), Browser (close tab),
│                   AXTextReader (tier 1a, to build), ScreenTextReader (tier 1b, stub)
├── Intelligence/   DistractionClassifier, CascadeClassifier, RuleBasedClassifier,
│                   EmbeddingMatcher (tier 2, to build), FoundationModelJudge (tier 3, to build), Hysteresis
├── Enforcement/    ShieldController (NSWindow at .screenSaver + presentationOptions), ShieldView, ShieldPolicy
└── UI/             MenuBarView, SettingsView, PermissionsManager
```

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
- **M1 Strict MVP:** launch at login (`SMAppService`), a headless watchdog mode of the same binary registered as a keep-alive launch agent, block quitting and uninstall during Locked, first-run onboarding (plain-language "what steals your time?" → rules → permissions → guided demo shield), a nudge HUD for `nudge` verdicts, settings polish.
- **M2 AI v1:** `AXTextReader` and `ScreenTextReader` both built, instrumented and compared per PRD §8.3; `EmbeddingMatcher`; `FoundationModelJudge` with guided generation; rabbit-hole detection.
- **M3 Beta:** Network Extension hostname backstop (verify the non-MDM approval path first), weekly insights, Sparkle, notarized beta.
- **M4 AI v2:** VLM tier (and the downloader it needs), doomscroll detection, on-device adapter from "wrong call" feedback.
