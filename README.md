# Shift

**Local AI App & Website Blocker for macOS.** Cold Turkey-level strictness, but it understands what's on your screen.

See [PRD.md](PRD.md) for the full product spec.

## Run the demo

1. Open `Shift.xcodeproj` in Xcode 16 or later (macOS 14+, Apple Silicon).
2. Select the **Shift** target → *Signing & Capabilities* → pick your team.
3. Press **Cmd+R**. Shift lives in the menu bar (the ◎ icon). There's no Dock icon.

### Try it
- **Preview the shield:** menu bar → *Preview shield* → Strike 1/2/3. This shows each escalation level without closing anything.
- **Real session:** type a goal ("Finish thesis chapter"), pick **Firm**, press *Start focus*, then open `instagram.com` or `youtube.com/shorts` in Safari or Chrome.
  - About 2–3 seconds later the shield covers every display.
  - *Close this tab* closes only that tab. A native app such as Discord gets *Force quit*.
  - Do it again and you'll see the 15-second countdown, then the typed phrase.
  - `youtube.com` itself stays allowed; only Shorts is blocked (path-aware rules).
- **What Shift sees:** the menu bar panel shows the live app, window, page and verdict.
- **Locked mode:** you can't end the session or quit Shift until the timer runs out.

### Permissions you'll be asked for
| Permission | Why |
|---|---|
| Accessibility | Window titles |
| Automation → Safari/Chrome/Arc… | Read the tab URL, close the tab |

Tip: while developing, macOS ties permissions to the code signature. If prompts keep coming back after rebuilds, remove Shift from *Privacy & Security* and grant it again.

## Project layout

```
Shift/
├── App/            ShiftApp (menu bar + settings scenes), AppModel (orchestration)
├── Models/         FocusSession, Strictness, ScreenContext, Verdict, BlockRules, ActivityEvent
├── Detection/      ContextMonitor, WindowInspector (AX), Browser (AppleScript), ScreenTextReader (P1 stub)
├── Intelligence/   DistractionClassifier + CascadeClassifier, RuleBasedClassifier, LocalIntentModel (P1 stub), Hysteresis
├── Enforcement/    ShieldController (windows + system lockdown), ShieldView, ShieldPolicy (escalation)
└── UI/             MenuBarView, SettingsView, PermissionsManager
```

The project uses Xcode's folder-synced groups, so new `.swift` files dropped into `Shift/` are picked up automatically.

## Flow

```
ContextMonitor ──sample──▶ AppModel.handle
                              │ CascadeClassifier (rules now, local model in M2)
                              │ Hysteresis (2 consistent readings)
                              ▼
                         ShieldController.present ──▶ close tab / force quit / wrong call
```

## Next (see PRD §16)
- **M1:** Locked-mode hardening (login item, watchdog helper), onboarding, rule editor polish.
- **M2:** ScreenCaptureKit + Vision OCR, MLX intent classifier, model downloader.
