# Shift — Product Requirements Document

**Product:** Shift: Local AI App & Website Blocker for macOS
**Platform:** macOS 14+ (Apple Silicon only)
**Status:** Draft v0.1 · November 2026
**Owner:** beingpax

> Working name. Check App Store, trademark and domain availability before launch.

---

## 1. Summary

Shift is a strict distraction blocker for the Mac, in the spirit of Cold Turkey Blocker. The difference is that it understands what is on your screen. Instead of matching a list of domains, Shift uses a small on-device AI model to judge whether what you're looking at fits the goal you set for this focus session. When it doesn't, a full-screen frosted shield covers everything, and the only way out is to close the tab or quit the app.

Everything runs locally. No screenshots, text or browsing history ever leave the Mac.

**One-line pitch:** *The blocker that sees your screen, and never sends it anywhere.*

## 2. Problem

- **Domain lists are blunt.** YouTube is a lecture *and* Shorts. Reddit is r/swift *and* r/all. Today's blockers force an all-or-nothing choice, so people either over-block (and disable the blocker) or under-block (and drift).
- **Easy blockers get bypassed.** Opening a new browser, using a desktop app, or simply turning the blocker off defeats most tools. Cold Turkey wins because it's hard to escape, but it's rigid and dated.
- **Drift happens inside "allowed" apps.** The real time sink is the rabbit hole: you start on Stack Overflow and 20 minutes later you're reading about Roman aqueducts. No blocker catches this today.
- **Cloud AI is a non-starter.** Nobody will stream their screen to a server to stay focused.

## 3. Goals and non-goals

### Goals
1. Block distractions based on **intent** (session goal plus screen content), not only domains.
2. Be **as strict as Cold Turkey** when the user asks for it.
3. Keep **zero network dependency** for detection; 100% local inference.
4. Stay **invisible when you're on task**: under 3% average CPU and under 400 MB RAM when idle.
5. **Never block legitimate work**: a target false-positive rate below 1 per 10 focus hours.

### Non-goals (v1)
- iOS, iPadOS, Windows or Android.
- Parental control or monitoring other people.
- Cloud sync, accounts or team features.
- Intel Macs.

## 4. Target users

| Persona | Pain | What wins them |
|---|---|---|
| **Developer / indie maker** | YouTube and X rabbit holes during builds | Allows docs and tutorials, blocks feeds |
| **Student / researcher** | Needs YouTube lectures and Reddit threads for study | Rules by intent: "YouTube for lectures only" |
| **Writer / knowledge worker** | Drifts between tabs while "researching" | Rabbit-hole detection |
| **Self-diagnosed ADHD** | Willpower-based tools fail | Strict mode, escalating friction |

## 5. Positioning

| | Cold Turkey | Freedom | Opal / one sec | **Shift** |
|---|---|---|---|---|
| Blocks by | Domain / app | Domain / app | App + friction | **Intent + screen content** |
| Strictness | Very high | High (Locked Mode) | Medium | **Configurable up to very high** |
| Understands context | No | No | No | **Yes, local AI** |
| Privacy | Local | Cloud account | Cloud account | **Local only** |
| Mac-native feel | Dated | Cross-platform | Mixed | **SwiftUI, Liquid Glass** |

## 6. Core concepts

- **Focus Session:** a goal ("Finish chapter 3 of my thesis"), a duration and a strictness level. Everything Shift decides is relative to the active session's goal.
- **Rules:** user-written, plain-language constraints ("YouTube only for lectures", "Never Instagram"). They're compiled into fast rules plus classifier context.
- **Verdict:** `allow`, `nudge` (uncertain or mild drift) or `block` (confident distraction), each with a one-line reason the user can read.
- **Strike:** each enforced block in a session. Friction escalates with every strike.
- **Strictness:** `Gentle`, `Firm` or `Locked` (see §9).

## 7. Features

### P0 — MVP
- Menu bar app: start a session with a goal, duration and strictness.
- Context monitor: frontmost app, window title (Accessibility) and browser URL (Apple Events).
- Rule-based classifier with sensible defaults, plus a user blocklist and allowlist.
- Path-aware rules (`youtube.com/shorts` blocked while `youtube.com` stays allowed).
- **Full-screen shield** on all displays and Spaces, with escalating friction.
- Shield actions: **close tab** (browsers), **force quit** (native apps), **wrong call** (teaches the allowlist).
- Hysteresis: a block requires two consistent readings.
- Locked sessions can't be ended or quit early.
- "What Shift sees" panel: live view of the current context and verdict.

### P1 — AI v1
- On-screen text via ScreenCaptureKit and Vision OCR, change-driven only.
- Local text intent classifier (about 300 MB) judging *goal vs. screen*.
- Plain-language rule onboarding ("I lose hours to X and YouTube") that produces rules.
- Rabbit-hole detection (topic drift over time within allowed apps).
- Network Extension content filter as a backstop that doesn't depend on the AI.
- Privileged helper and watchdog that relaunch Shift if it's killed.

### P2 — AI v2 and polish
- Vision-language model (about 1 GB, 4-bit) for image- or video-heavy screens.
- Doomscroll detection (scroll velocity plus feed layout).
- Personal LoRA adapter trained on-device from "wrong call" feedback.
- Calendar-aware automatic sessions.
- Weekly local insights recap.
- Accountability partner unlock codes.

## 8. Detection pipeline

A cheap-first cascade. Most decisions never touch the AI.

```
Event (app switch, title change, URL change, screen diff)
   │
   ├─ Tier 0  Free signals ............ bundle ID, window title, URL         ~0 ms
   │          → rules decide ~90% of cases (definite allow / definite block)
   │
   ├─ Tier 1  On-screen text .......... ScreenCaptureKit + Vision OCR (ANE)  ~20 ms
   │          only on change, never on a fixed timer
   │
   ├─ Tier 2  Intent classifier ....... (goal, url, title, ocr) → verdict    ~50 ms
   │          ~300 MB, always resident
   │
   └─ Tier 3  Vision-language model ... only when Tier 2 is uncertain        ~400 ms
              ~1 GB 4-bit, loaded on demand, unloaded after 5 min idle
   │
   ▼
Hysteresis (2–3 consistent readings) → Enforcement
```

**Rules of the pipeline**
- Events drive work. A perceptual-hash screen diff gates OCR. Nothing polls at high frequency.
- When confidence is low on a work-type app (IDE, terminal, docs), **default to allow**.
- Every verdict carries a human-readable reason.

## 9. Enforcement and shield UX

### Shield
- A borderless window at screen-saver level on **every display**, joining all Spaces and full-screen apps.
- While it's up: the Dock and menu bar are hidden, and app switching (Cmd+Tab) and Hide are disabled.
- Frosted-glass background: you can see what's behind it but can't touch it.
- Content: "Not now.", the AI's reason, the session goal, a strike count, and one primary action.

### Primary action
| Context | Action |
|---|---|
| Browser tab | **Close this tab** (never quit a browser with 30 work tabs over one tab) |
| Native app (Discord, Steam…) | **Force quit** the app |
| Browser that keeps returning (P1) | Force quit the browser |

### Escalation by strictness
| Strike | Gentle | Firm | Locked |
|---|---|---|---|
| 1 | Immediate | Immediate | 10 s countdown |
| 2 | Immediate | 15 s countdown | 30 s countdown |
| 3+ | Immediate | 15 s + type phrase | 30 s + type phrase |

The phrase is *"I am choosing to get distracted"*.

- **Nudge** verdicts never show the shield. They show a small, dismissible HUD (P1).
- **Wrong call** is only available once the countdown has finished, so it can't be used as an escape hatch. It adds the host or app to the session allowlist and logs a training example.

### Anti-bypass (Locked)
- The session can't be ended and Shift can't be quit until the timer ends.
- P1: a launch agent and privileged helper relaunch the app, and a watchdog pair revives each other if one is killed.
- P1: a Network Extension filter blocks hard-blocked domains even if the UI process dies.
- P1: block changes to the clock and time zone, uninstall, and the relevant System Settings panes during a lock.
- **Honesty:** an admin user can always win. Shift sells friction, not a prison, and says so.

## 10. Local AI models and model management

| Model | Purpose | Size | Runtime | Residency |
|---|---|---|---|---|
| Intent classifier | (goal, context, OCR) → allow/nudge/block + reason | ~300 MB | MLX / Core ML | Always loaded during sessions |
| Vision-language model | Screens with little text (video, images) | ~1 GB (4-bit) | MLX | Loaded on demand, unloaded after 5 min idle |
| Personal adapter | Learns the user's corrections | <20 MB LoRA | MLX | Merged at load |

**Delivery**
- Models are **not bundled**. The app ships at under 30 MB and downloads models on first run behind a friendly progress screen.
- Files are hosted on a CDN with signed manifests (SHA-256 per file). Updates are delta-patched and verified before swapping.
- Stored in `~/Library/Application Support/Shift/Models/<model>/<version>/`. Keep N and N-1 for rollback.
- **The rule-based tier works with no model at all**, so Shift is useful the moment it's installed.

**Training**
- Distillation: a large teacher model labels a mix of synthetic screens and real anonymized OCR dumps (opt-in, donated, never automatic).
- Base candidates: a small Qwen- or SmolVLM-class model, fine-tuned for a structured `{verdict, confidence, reason}` output.
- Eval set: about 5k labeled (goal, screen) pairs. Ship gate: under 1% false blocks on work apps, over 90% recall on obvious distractions.

## 11. Privacy

- No screenshots or OCR text are written to disk. Frames live in memory for the duration of one inference.
- No analytics on content. Optional crash reports only.
- **"What Shift saw"** panel shows the last context and verdict, so the AI isn't a black box.
- Network use is limited to model downloads and update checks, and is listed in Settings.

## 12. Permissions and onboarding

| Permission | Why | When requested |
|---|---|---|
| Accessibility | Window titles; disabling shortcuts during the shield | Onboarding step 2 |
| Automation (Apple Events) per browser | Read the current URL, close the tab | First time each browser is seen |
| Screen Recording (P1) | OCR / vision tiers | When the AI tier is enabled |
| Network Extension (P1) | Network-level backstop | Optional, strict users |

Onboarding flow:
1. Plain-language prompt: "What steals your time?"
2. Generated rules.
3. Permissions, each explained in one line.
4. A first 25-minute session with a guided demo shield.

macOS periodically asks users to re-approve Screen Recording. Detect when it's missing and degrade to Tier 0 with a gentle banner. Never break silently.

## 13. Architecture

- **Language/UI:** Swift 5.10+, SwiftUI (menu bar plus settings), AppKit for shield windows.
- **Distribution:** Developer ID signed and notarized, outside the Mac App Store (the sandbox blocks Accessibility automation, the shield level and the helper). Updates via Sparkle.
- **Frameworks:** AppKit, ApplicationServices (AX), ScreenCaptureKit, Vision, MLX Swift, NetworkExtension, ServiceManagement (SMAppService).

### Module map (matches the Xcode skeleton)
```
Shift/
├── App/            ShiftApp (scenes), AppModel (session state + orchestration)
├── Models/         FocusSession, Strictness, ScreenContext, Verdict, BlockRules, ActivityEvent
├── Detection/      ContextMonitor, WindowInspector (AX), Browser (URL + tab control), ScreenTextReader (P1 stub)
├── Intelligence/   DistractionClassifier, RuleBasedClassifier, LocalIntentModel (P1 stub), Hysteresis
├── Enforcement/    ShieldController, ShieldWindow, ShieldView, ShieldPolicy
├── UI/             MenuBarView, SettingsView, PermissionsManager
└── Assets.xcassets
```

## 14. Success metrics

- **Activation:** % of installs that finish a first session (target 60%).
- **Retention:** week-4 retention of users who started 3+ sessions (target 35%).
- **Trust:** "wrong call" taps per 10 focus hours (target under 1).
- **Efficacy:** self-reported focus improvement in the weekly recap; shield frequency trending down over 4 weeks.
- **Performance:** idle CPU under 3%, p95 verdict latency under 150 ms (Tiers 0–2).

## 15. Risks and mitigations

| Risk | Mitigation |
|---|---|
| False positive blocks real work (users uninstall) | Default to allow on work apps; hysteresis; "wrong call"; shield only above the confidence threshold |
| Screen Recording re-approval prompts | Detect, degrade gracefully, explain in one line |
| Battery and thermals | Event-driven OCR, change detection, on-demand VLM, ANE-backed Vision |
| Bypass by power users | Layered helper, watchdog and NE filter; honest marketing |
| AppleScript latency or hangs | Per-browser timeouts; move to a browser extension in P1 |
| Name conflicts ("Shift") | Verify trademark and domain before branding spend |

## 16. Milestones

| Milestone | Scope | Target |
|---|---|---|
| **M0 Skeleton** | This repo: menu bar app, rules, shield, escalation | Done |
| **M1 Strict MVP** | Locked mode hardening, helper/watchdog, onboarding, settings polish | +3 weeks |
| **M2 AI v1** | OCR tier, intent classifier, model downloader, rabbit-hole detection | +6 weeks |
| **M3 Beta** | NE filter, insights, Sparkle, notarized public beta | +4 weeks |
| **M4 AI v2** | VLM tier, doomscroll detection, personal adapter | Post-beta |

## 17. Open questions

1. Pricing: one-time (as Cold Turkey does, around $39) or subscription for model updates?
2. Do we offer an accountability-partner unlock in v1 or later?
3. Is a browser extension worth it in P1 for exact URLs and in-page signals, versus AppleScript only?
4. What's the minimum Mac (8 GB RAM) experience for the VLM tier? Do we disable it automatically?
