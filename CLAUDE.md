# Shift: context for Claude

Shift is a **macOS-only, local-AI app and website blocker**: Cold Turkey-level strictness, but it understands what's on screen. Read `PRD.md` for the full spec; this file is the working memory of decisions already made.

Local folder: `~/Shift Focus`. Repo: https://github.com/Beingpax/Shift-Focus (branch `main`). Owner: Prakash Joshi Pax (`Beingpax`).

## Current status (read first)

- **The code has never been compiled.** It was written without Xcode available. Job #1 in any new session is a clean build: fix every error and warning, then run it.
- Built and wired: menu bar app, focus sessions, context monitor (frontmost app, AX window title, browser URL via AppleScript), rule-based classifier, hysteresis, full-screen shield with escalation, settings tabs.
- Stubs only: `ScreenTextReader` (OCR tier) and `LocalIntentModel` (MLX model tier).

## Build and run

```bash
xcodebuild -project Shift.xcodeproj -scheme Shift -configuration Debug -destination 'platform=macOS' build
```

- Run from Xcode with Cmd+R. Shift is an `LSUIElement` menu bar app (◎ icon), with no Dock icon.
- Test the shield without side effects: menu bar → *Preview shield* → Strike 1/2/3.
- Real test: start a Firm session, open `instagram.com` or `youtube.com/shorts` in Safari or Chrome. The shield should appear in about 2–3 seconds.
- Permissions: Accessibility (window titles) and Automation per browser (URL, close tab). They're tied to the code signature, so re-grant after signing changes.

## Product decisions (don't relitigate without asking)

- **Name:** "Shift", subtitle "Local AI App & Website Blocker". Mac only, Apple Silicon, macOS 14+.
- **Everything is local.** Never send screen content, OCR text or URLs off the device.
- **Detection is a cheap-first cascade:** rules → OCR (change-driven, never on a timer) → small intent classifier (~300 MB) → VLM (~1 GB, on demand). Rules must work with no model installed.
- **Intent over domains:** judge the screen against the session's goal. Path-aware rules (`youtube.com/shorts` blocked, `youtube.com` allowed).
- **Shield:** frosted full-screen window on every display and Space; while it's up, the Dock, menu bar and Cmd+Tab are disabled. The text says "Not now." plus a one-line reason.
  - Browsers: **close the tab, never quit the browser.** Native apps: force quit.
  - **Escalation:** Firm = strike 1 immediate, strike 2 a 15 s countdown, strike 3+ 15 s plus typing *"I am choosing to get distracted"*. Locked = 10 s / 30 s / 30 s plus the phrase. Gentle = always immediate.
  - **"Wrong call"** only unlocks after the countdown (it must not be an escape hatch). It allows that host or app for the session.
  - Only confident blocks show the shield; nudges never do. Default to allow on work apps when unsure.
- **Locked mode:** you can't end the session or quit Shift early.
- **Honesty:** an admin can always win. We sell friction, not a prison.

## Architecture

```
Shift/
├── App/            ShiftApp (MenuBarExtra + Settings), AppModel (@Observable, @MainActor orchestrator)
├── Models/         FocusSession, Strictness, ScreenContext, Verdict, BlockRules, ActivityEvent
├── Detection/      ContextMonitor, WindowInspector (AX), Browser (AppleScript URL/close tab), ScreenTextReader (stub)
├── Intelligence/   DistractionClassifier, CascadeClassifier, RuleBasedClassifier, LocalIntentModel (stub), Hysteresis
├── Enforcement/    ShieldController (NSWindow at .screenSaver + presentationOptions), ShieldView, ShieldPolicy
└── UI/             MenuBarView, SettingsView, PermissionsManager
```

Flow: `ContextMonitor` sample → `AppModel.handle` → `CascadeClassifier` → `Hysteresis` (2 consistent readings) → `ShieldController.present` → resolve (close tab / force quit / wrong call).

## Conventions

- Swift 5 language mode, SwiftUI plus AppKit where needed, `@Observable`, macOS 14 APIs are fine.
- **Not sandboxed**, Hardened Runtime on, entitlement `com.apple.security.automation.apple-events`. Distribution: Developer ID plus notarization (no Mac App Store).
- The Xcode project uses **folder-synced groups** (`PBXFileSystemSynchronizedRootGroup`): new files in `Shift/` are picked up automatically, so don't hand-edit file references into `project.pbxproj`.
- Keep the UI native and calm; the shield is the only loud surface.
- Small, focused commits on `main`, pushed to `origin`.

## Roadmap (PRD §16)

- **M0 Skeleton:** done (pending first clean build).
- **M1 Strict MVP:** launch at login (`SMAppService`), a watchdog helper that relaunches Shift if killed, block quitting and uninstall during Locked, first-run onboarding (plain-language "what steals your time?" → rules → permissions → guided demo shield), settings polish, a nudge HUD for `nudge` verdicts.
- **M2 AI v1:** ScreenCaptureKit + Vision OCR (change-gated), MLX intent classifier, model downloader with signed manifest, rabbit-hole detection.
- **M3 Beta:** Network Extension filter backstop, weekly insights, Sparkle, notarized beta.
- **M4 AI v2:** VLM tier, doomscroll detection, on-device LoRA from "wrong call" feedback.
