# Fence — Product Requirements Document

**Product:** Fence: Local App & Website Blocker for macOS
**Platform:** macOS 26+ (Apple Silicon only)
**Status:** Draft v0.2 · November 2026
**Owner:** beingpax

> Working name. Check App Store, trademark and domain availability before launch.

> **v0.2 changes.** Competitive research found that "AI blocker that checks your screen
> against your goal" shipped in several products during v0.1. Technical research replaced
> three of v0.1's biggest bets: the 300 MB downloaded classifier is gone in favour of
> Apple's built-in Foundation Models; OCR is no longer the only way to read a screen;
> and the OS floor moves to macOS 26 to make both possible. See §17 for the full delta.

---

## 1. Summary

Fence is a local distraction blocker for the Mac. An active website, path, or app rule can raise a full-screen shield. Optional nudges use keywords in window titles.

The semantic detection and Screen Recording material elsewhere in this draft describes earlier plans. The current app uses explicit rules and Accessibility window metadata.

## 2. Problem

- **Domain lists are blunt.** YouTube is a lecture *and* Shorts. Reddit is r/swift *and* r/all. Today's blockers force an all-or-nothing choice, so people either over-block (and disable the blocker) or under-block (and drift).
- **Easy blockers get bypassed.** Opening a new browser, using a desktop app, or simply turning the blocker off defeats most tools.
- **Drift happens inside "allowed" apps.** The real time sink is the rabbit hole: you start on Stack Overflow and 20 minutes later you're reading about Roman aqueducts.
- **Cloud AI is a non-starter.** Nobody will stream their screen to a server to stay focused.

## 3. Goals and non-goals

### Goals
1. Block explicit website, path and app matches. Offer optional reminders based on a focus goal and screen content.
2. Be **strict** when the user asks for it: hard to switch off and hard to escape.
3. Keep **zero network dependency** for detection. 100% local inference, and nothing to download.
4. Stay **invisible when you're on task**: under 3% average CPU and under 400 MB RAM when idle.
5. **Never block legitimate work**: a target false-positive rate below 1 per 10 focus hours.
6. **Keep battery cost low**, by preferring exact text over pixels.

### Non-goals (v1)
- iOS, iPadOS, Windows or Android.
- Parental control or monitoring other people.
- Cloud sync, accounts or team features.
- Intel Macs, and Macs below macOS 26.

## 4. Target users

| Persona | Pain | What wins them |
|---|---|---|
| **Developer / indie maker** | YouTube and X rabbit holes during builds | Allows docs and tutorials, blocks feeds |
| **Student / researcher** | Needs YouTube lectures and Reddit threads for study | Rules by intent: "YouTube for lectures only" |
| **Writer / knowledge worker** | Drifts between tabs while "researching" | Rabbit-hole detection |
| **Self-diagnosed ADHD** | Willpower-based tools fail | Strict mode, escalating friction |

## 5. Core concepts

Fence is organised around **blocks**, not sessions. This changed in v0.3 after testing the
session model against real use: a one-off timer can't express "social media is never
allowed", "no news before noon", or "games are off on weeknights", and those are the rules
people actually want. The block is the correct unit.

- **Block:** a named, independently configured rule set. It owns what it covers, when it
  applies, and when it can be switched off. Blocks are
  switched on and off one at a time and several can be active at once.
- **List:** website domains, paths, and apps to block.
- **Schedule:** Always, recurring Schedule, or None. A block with None starts as a timed
  run from the block’s menu bar context menu.
- **Lock:** whether the user may switch a block off. Engages the moment the block is
  switched on. Methods: none, for a duration, until a time, after typing a random string,
  or until the Mac restarts.
- **Break:** optional 2 or 5 minutes of access for the rule that triggered the shield, after a one-minute wait.
  Each block allows two starts per day, resetting at local midnight.
- **Verdict:** `allow`, `nudge` (mild drift) or `block` (explicit rule match), each with a
  one-line reason and the block that produced it.
- **Strike:** each enforced hit, counted separately for the matched rule within a block.
  Counts reset at local midnight.
- **Goal:** an optional intent sentence per block, shown on the shield and the input to
  the intent tier when it lands.

## 6. Features

### P0 — MVP
- Menu bar app plus a main window with a sidebar: Dashboard, Blocks, Activity.
- Create, edit, order and delete blocks, each with its own list, schedule and lock.
- Context monitor: frontmost app, window title and browser URL.
- Rule-based classifier with sensible defaults and editable website and app lists.
- Path-aware rules (`youtube.com/shorts` blocked while `youtube.com` stays allowed).
- **Full-screen shield** on all displays and Spaces, with escalating friction.
- Shield actions: **quit the browser or app**, and **take a break** when configured.
- Hysteresis: a block requires two consistent readings.
- Locked blocks can't be switched off, edited loosely, deleted, and Fence can't be quit.
- "What Fence sees" panel: live view of the current context and verdict.

### P1 — Strict MVP
- Launch at login, plus a watchdog that relaunches Fence if it's killed mid-session.
- Block quitting and uninstalling during a Locked session.
- Plain-language rule onboarding ("I lose hours to X and YouTube") that produces rules.
- Nudge HUD for `nudge` verdicts.
- Settings polish.

### P2 — AI v1
- Page text from the **Accessibility tree** and, in parallel, from **OCR**. Both are built and compared (§7.3).
- Goal-vs-screen judgment through **Apple's Foundation Models** framework.
- Embedding-based semantic pre-filter below the model.
- Rabbit-hole detection (topic drift over time within allowed apps).

### P3 — Beta
- Network Extension content filter as a hostname backstop that doesn't depend on the AI.
- Sparkle updates and notarized public beta.

### P4 — AI v2 and polish
- Vision-language model for image- or video-heavy screens, where neither AX text nor OCR helps.
- Doomscroll detection (scroll velocity plus feed layout).
- Personal adapter trained on-device from explicit feedback during evaluation.
- Calendar-aware automatic sessions.
- Accountability partner unlock codes.

## 7. Detection pipeline

A cheap-first cascade. Most decisions never touch the model.

```
Event (app switch, title change, URL change, AX text change, screen diff)
   │
   ├─ Tier 0  Free signals ......... bundle ID, window title, URL            ~0 ms
   │          → rules decide ~90% of cases (definite allow / definite block)
   │
   ├─ Tier 1a AX page text ......... exact strings from the accessibility tree  ~5 ms
   ├─ Tier 1b OCR .................. ScreenCaptureKit + Vision on demand       ~20 ms
   │          1a and 1b are both built in P2 and compared; see §7.3
   │
   ├─ Tier 2  Embedding match ...... goal vs text, NLContextualEmbedding     ~10 ms
   │          resolves obvious matches without waking the LLM
   │
   ├─ Tier 3  Foundation Models .... (goal, context) → activity label        ~300–800 ms
   │          built into macOS, no download, guided generation
   │
   └─ Tier 4  Vision-language model  image-heavy screens only (P4)
   │
   ▼
Consistent rule matches → Shield
Sustained evidence of unrelated leisure → Nudge
```

**Rules of the pipeline**
- Context changes and pending nudge confirmations drive text sampling.
- Ambiguous or unavailable evidence leaves the current activity alone.
- Every verdict carries a human-readable reason.
- Shield enforcement requires an explicit rule match.

### 7.1 Tier 1a — Accessibility text (preferred channel)

Both Safari and Chrome expose their rendered page to macOS as an accessibility web area. Its URL is readable as an attribute, and the visible text is readable as element values. Compared with OCR this is exact text rather than recognition: correct Unicode, correct casing, no confidence score to threshold, no frame capture, and no Screen Recording permission.

It also lets us read the **URL from the accessibility tree** without a per-browser Automation prompt.

**Known hazards, to be settled by the P2 spike:**
- Chromium and Electron build their accessibility trees lazily. Chrome populates page content only for a client that sets `AXEnhancedUserInterface` on the application element; Electron apps need `AXManualAccessibility`.
- Success is confirmed by reading the attribute back, not by the API return code. Chrome reports not-implemented even when it worked.
- The tree fills asynchronously. Expect to retry after roughly 150 ms, and expect Chrome to enable page content about two seconds after the last change.
- Setting those attributes is the same signal an assistive client sends, so watch for side effects and renderer overhead in Chrome.
- Arc and Brave are Chromium and should behave like Chrome, but must be tested individually.

### 7.2 Tier 1b — OCR

The original v0.1 plan, retained as a full channel rather than a stub:
1. `SCShareableContent` finds the frontmost window's `SCWindow`.
2. `SCScreenshotManager.captureImage` with a single-window filter, scaled to about 1280 px.
3. `VNRecognizeTextRequest` in fast mode, capped at about 2k characters.
4. Frames stay in memory for the duration of the sample.

OCR covers what the accessibility tree cannot: canvas-rendered apps, video, games, images, and any app with a hostile or absent AX tree. It needs Screen Recording permission, so it must degrade cleanly when that is missing.

### 7.3 Tier 1 bake-off and decision gate

AX text and OCR are built together in P2 with equal weight, then compared on real usage before either is made the default. Both run behind the same `ScreenTextReading` protocol so the cascade does not care which answered.

Instrument every sample with the channel used, latency, and characters returned. Compare over at least two weeks of daily use across Safari, Chrome, Arc, Brave, and a set of native and Electron apps.

| Metric | Gate |
|---|---|
| Coverage: samples returning usable text | AX must clear 80% in browsers to become default there |
| Agreement: verdicts matching the other channel | Investigate every disagreement above 5% |
| Latency p95 | AX under 50 ms, OCR under 150 ms |
| Idle CPU during a session | Whole-app average under 3% |
| Unwanted nudges per 10 focus hours | Under 1 for the chosen default |

Expected outcome, to be confirmed rather than assumed: AX text becomes the default for browsers and AX-capable native apps, and OCR becomes the fallback for everything else and for when Accessibility text comes back empty. If Chromium proves unreliable, OCR becomes the default for Chromium browsers specifically, per-browser rather than globally.

### 7.4 Tier 3 — Foundation Models

Apple's Foundation Models framework exposes the on-device model behind Apple Intelligence: roughly 3 billion parameters, aggressively quantized, running on the Neural Engine.

**Why it replaces the v0.1 downloaded classifier**
- Nothing to download, so the model downloader, the signed CDN manifest, the version directories and the 300 MB payload all disappear from scope.
- Free, offline and private by construction.
- Guided generation returns one activity label from `work`, `unclear` and `unrelatedLeisure`.
- Measured performance fits the budget: about 0.6 ms per prompt token to first token, then 30–50 tokens per second.
- On macOS 27 Apple removed the switch that turns Apple Intelligence off, so on supported hardware the model is simply present.

**Constraints that shape the prompt**
- The context window is about 4,096 tokens and covers instructions, prompt, output and any tool definitions together. We send a trimmed extract of page text, never a whole page. Budget roughly 2,500 tokens of page text.
- Availability must still be checked at runtime. Handle the unavailable cases and fall back to tiers 0–2 rather than failing.
- Apple warns the model is unsuited to world knowledge and factual recall. Our task is classification against a user-supplied goal, which is in scope.

Model refusals, guardrails and other inference failures are treated as unclear. Fence chooses the action after evaluating the activity label.

### 7.5 Tier 2 — Embeddings

Apple's natural language contextual embeddings use available on-device assets to resolve obvious matches to any active goal before calling the model.

Calibration matters. Unrelated short strings score deceptively high, so compare sentence-length or phrase-length text, not single words, and tune thresholds against the eval set rather than guessing.

## 8. Enforcement and shield UX

### Platform limit, recorded deliberately
Apple's Screen Time frameworks (FamilyControls, ManagedSettings, DeviceActivity) are **iOS and iPadOS only and are not available on macOS in any capacity**. There is no OS-level app shield to borrow on the Mac. Enforcement therefore has to be app-level (quit the browser or app) plus process-level persistence (watchdog) plus an optional network backstop. This is why §8's anti-bypass section ends in an honesty clause rather than a guarantee.

### Shield
- A borderless window at screen-saver level on **every display**, joining all Spaces and full-screen apps.
- While it's up: the Dock and menu bar are hidden, and app switching (Cmd+Tab) and Hide are disabled.
- Frosted-glass background: you can see what's behind it but can't touch it.
- Content: "Not now.", the reason, the session goal, a strike count, and one primary action.

### Primary action
| Context | Action |
|---|---|
| Browser | **Quit** the entire browser |
| Native app (Discord, Steam…) | **Quit** the app |

### Automatic shield escalation

| Strike | Level | Primary action availability |
|---|---|---|
| 1 | Gentle | Immediate |
| 2 | Firm | After 15 seconds |
| 3+ | Severe | After 30 seconds and typing the phrase |

The quit action stays the same across levels. The phrase is *"I am choosing to get distracted"*.
Nudge verdicts show a dismissible HUD.

### Anti-bypass (Locked)
- The session can't be ended and Fence can't be quit until the timer ends.
- P1: a headless watchdog mode of the same binary, registered as a keep-alive launch agent through `SMAppService`, relaunches Fence if the main process dies.
- P1: block uninstalling the app during a lock.
- P3: a Network Extension content filter blocks hard-blocked hostnames even if the UI process dies (§9.2).
- P1: block changes to the clock and time zone, and the relevant System Settings panes, during a lock.
- **Honesty:** an admin user can always win. Fence sells friction, not a prison, and says so.

## 9. Platform mechanisms

### 9.1 On-device models

| Model | Purpose | Size | Runtime | Residency |
|---|---|---|---|---|
| Apple Foundation Models | (goal, context) → activity label | 0 bytes shipped by us | Built into macOS 26+ | System-managed |
| Contextual embeddings | Cheap goal-vs-text similarity | 0 bytes shipped by us | Built into macOS | System-managed |
| Vision-language model (P4) | Screens with little text: video, images, games | ~1 GB, 4-bit | MLX | On demand, unloaded after 5 min idle |
| Personal adapter (P4) | Learns the user's corrections | <20 MB | MLX or framework adapter | Merged at load |

**Delivery.** P2 ships with **nothing to download**. The app stays under 30 MB and the semantic tiers work the moment it's installed. A downloader is only reintroduced in P4, for the vision-language tier, and only then do signed manifests, version directories and rollback become relevant.

**The rule-based tier still works with no model at all**, so Fence degrades to a strict conventional blocker rather than breaking.

**Evaluation.** Build an eval set of about 5k labelled (goal, screen) pairs from synthetic screens plus opt-in donated extracts. Ship gate: under 1% false blocks on work apps, over 90% recall on obvious distractions. Because the model is Apple's, our tuning surface is the prompt, the trimming strategy and the thresholds, not the weights. Pin prompt behaviour with snapshot tests so an OS update that changes the model is caught by CI rather than by users.

### 9.2 Network backstop, and what we rejected

**Chosen (P3):** a `NEFilterDataProvider` content filter shipped as a system extension inside the app bundle and activated through a system extension request.
- Non-MDM installs are approved by the user under System Settings, Login Items and Extensions. Developer ID signing and notarization are required.
- Socket-level filtering sees hostnames, not paths, because HTTPS hides the path. This backstop is therefore **hostname-only and never path-aware**. Path-aware blocking stays in the app tiers.
- Known risk: there are reports of the system extension daemon on macOS 26 rejecting new content-filter activation with a "no policy" error on non-MDM machines with valid Developer ID and notarization, apparently failing to fall through to user approval. Verify on current macOS before committing P3 scope, and keep the feature optional.

**Rejected: the macOS 26 URL filter.** macOS 26 added full-URL filtering, which sounds like an exact fit for path-aware rules. It is not usable here: it requires a Bloom filter built from the URL data set, a Private Information Retrieval **server** for the app to query, and a dedicated entitlement. Requiring a server contradicts the no-network rule in §3 and §10. Revisit only if Apple allows a fully local data set.

**Rejected: hosts-file and DNS rewriting.** Effective and cheap, but it is coarse, hostname-only, invisible to the user, and hostile to debug. It also fights the same battle as the content filter for less clarity.

## 10. Privacy

- No screenshots, OCR text or accessibility text are written to disk. Content lives in memory for the duration of one inference.
- Inference happens on-device in every tier. There is no cloud fallback, even an optional one.
- No analytics on content. Optional crash reports only.
- **"What Fence saw"** panel shows the last context and verdict, so the decision isn't a black box. It should also name which tier decided.
- Network use in P2 is **none for detection**. Update checks only, and they are listed in Settings.

## 11. Permissions and onboarding

| Permission | Why | When requested |
|---|---|---|
| Accessibility | Window titles, page text, browser URL, disabling shortcuts during the shield | Onboarding step 2 |
| Screen Recording | OCR for optional focus reminders | Settings, optional |
| Network Extension (P3) | Hostname backstop | Optional, strict users only |

Accessibility provides window, page text, and URL detection. The quit action uses the standard macOS process termination request.

Onboarding flow:
1. Plain-language prompt: "What steals your time?"
2. Generated rules.
3. Permissions, each explained in one line, with Screen Recording presented as optional.
4. A first 25-minute session with a guided demo shield.

macOS periodically asks users to re-approve Screen Recording and Accessibility. Detect when either is missing, degrade to the tiers that still work, and say so in a gentle banner. Never break silently.

## 12. Architecture

- **Language/UI:** Swift 5 language mode, SwiftUI for the menu bar and settings, AppKit for shield windows.
- **Deployment target:** macOS 26.0, Apple Silicon. This is what makes Foundation Models a baseline assumption rather than an optional extra, and it removes every `#available` fork from the AI path.
- **Distribution:** Developer ID signed and notarized, outside the Mac App Store (the sandbox blocks Accessibility automation, the shield level and the system extension). Updates via Sparkle.
- **Frameworks:** AppKit, ApplicationServices (AX), FoundationModels, NaturalLanguage, ScreenCaptureKit, Vision, NetworkExtension, ServiceManagement, MLX Swift (P4 only).

### Module map (matches the Xcode skeleton)
```
Fence/
├── App/            FenceApp (scenes), AppModel (session state + orchestration)
├── Models/         FocusSession, Strictness, ScreenContext, Verdict, BlockRules, ActivityEvent
├── Detection/      ContextMonitor, WindowInspector (AX), Browser (tab control),
│                   AXTextReader (tier 1a), ScreenTextReader (tier 1b)
├── Intelligence/   DistractionClassifier, CascadeClassifier, RuleBasedClassifier,
│                   EmbeddingMatcher (tier 2), FoundationModelJudge (tier 3), Hysteresis
├── Enforcement/    ShieldController, ShieldWindow, ShieldView, ShieldPolicy
├── UI/             MenuBarView, SettingsView, PermissionsManager
└── Assets.xcassets
```

The `DistractionClassifier` and `ScreenTextReading` protocols in the skeleton are already the right seams. Tiers plug in behind them without touching `AppModel`.

## 13. Success metrics

- **Activation:** % of installs that finish a first session (target 60%).
- **Retention:** week-4 retention of users who started 3+ sessions (target 35%).
- **Trust:** false blocks per 10 focus hours in labeled evaluations (target under 1).
- **Efficacy:** self-reported focus improvement and fewer shield encounters over time in beta feedback.
- **Performance:** idle CPU under 3%, p95 verdict latency under 150 ms for tiers 0–2, under 1 s including tier 3.
- **Running cost:** a low, steady energy impact, measured in Activity Monitor over a one-hour session.

## 14. Risks and mitigations

| Risk | Mitigation |
|---|---|
| False positive blocks real work (users uninstall) | Default to allow on work apps; hysteresis; shield only above the confidence threshold |
| Chromium lazy accessibility tree makes tier 1a unreliable | §7.3 bake-off decides per browser; OCR is a full channel, not a stub, so falling back costs nothing |
| Foundation Models unavailable on a user's machine | Runtime availability check; tiers 0–2 carry the product; onboarding states the degraded mode plainly |
| Guardrail violations on ordinary page text | Treated as block evidence, never as failure or allow; reason line stays honest; rules still gate the final decision |
| An OS update changes Apple's model behaviour | Snapshot tests over the eval set in CI; prompt and thresholds are our only tuning surface, so keep them versioned |
| macOS 26 floor shrinks the market | Accepted deliberately; Apple Silicon was already required, and the AI story is the product |
| System extension approval regression on non-MDM Macs | Verify before committing P3; keep the network backstop optional |
| Battery and thermals | Prefer AX text over pixels; change-gated OCR; event-driven sampling; on-demand VLM |
| Bypass by power users | Layered watchdog and network filter; honest marketing |
| Name conflicts ("Fence") | Verify trademark and domain before branding spend |

## 15. Milestones

| Milestone | Scope | Target |
|---|---|---|
| **M0 Skeleton** | Menu bar app, rules, shield, escalation. Builds clean. | Done |
| **M1 Strict MVP** | Locked hardening, launch at login, watchdog, onboarding, nudge HUD, settings polish | +3 weeks |
| **M2 AI v1** | AX text and OCR channels, bake-off, embeddings, Foundation Models judge, rabbit-hole detection | +4 weeks |
| **M3 Beta** | NE hostname filter, Sparkle, notarized public beta | +4 weeks |
| **M4 AI v2** | VLM tier, doomscroll detection, personal adapter | Post-beta |

### Current implementation and remaining work

| Milestone | Implemented in code | Remaining |
|---|---|---|
| M0 / P0 | Block CRUD and ordering, schedule, locks, breaks, website and app rules, path rules, live context, recent activity, shield, two-reading hysteresis and per-rule daily escalation | Validate shield behavior across Spaces and displays, daily rollover, and timed starts with saved blocks. |
| M1 / P1 | Launch at login, user-level watchdog with Trash restoration, quit protection, preset-based onboarding, shield preview, settings and nudge HUD | Plain-language rule generation, guided 25-minute first block, clock and time-zone hardening, and live verification of watch and relaunch behavior. |
| M2 / P2 | Accessibility browser URLs and text, selective single-window OCR, installed-asset embedding pre-filter and on-device activity classification for optional nudges | Measure latency, missed distractions and unwanted nudges. |
| M3 / P3 | | Network Extension hostname backstop, Sparkle and notarized public beta. |
| M4 / P4 | | Vision-language model, doomscroll detection, on-device adaptation, calendar sessions and partner unlock codes. |

The current M2 policy prefers Accessibility text. OCR handles an absent or sparse Accessibility result when Screen Recording is granted. Screen frames and source text are transient.

A change of focused window, title or URL can trigger a new reading. If the model identifies leisure unrelated to every active goal, Fence takes a fresh reading after at least 15 seconds. A matching result from the same source in the same context can show one gentle reminder. Visual changes within a window that retains the same title and URL may go undetected. The capture permission flow, window selection, browser coverage and activity classification still require runtime verification.

M2 shrank from six weeks to four: the model downloader, signed manifest, version management and model training work are gone, offset by building two tier-1 channels instead of one.

## 16. Open questions

1. Pricing. A one-time purchase, with nothing sold monthly; the figure is open. Decide before any landing page.
2. Do we offer an accountability-partner unlock in v1 or later?
3. Is a browser extension still worth building? Reading the accessibility tree removes the original reason for one, which was exact URLs. An extension would still unlock per-feed-item filtering. Defer to post-M3 and decide on evidence from the bake-off.
4. Does the vision-language tier survive at all, given a 16 GB machine and Apple Intelligence already resident? Measure before committing P4 scope.
5. How do we present the macOS 26 requirement without sounding exclusionary on the landing page?

## 17. Delta from v0.1

| Area | v0.1 | v0.2 | Why |
|---|---|---|---|
| OS floor | macOS 14+ | macOS 26+ | Makes Foundation Models and modern APIs a baseline, removes every availability fork |
| Intent model | ~300 MB MLX classifier, downloaded, CDN, signed manifest | Apple Foundation Models, built in | Zero download, free, private, guided generation, no CDN to run |
| Screen reading | OCR only, AX for titles | AX page text and OCR as equal channels, compared on real usage | AX text is exact and nearly free; OCR still covers canvas, video and hostile apps |
| Browser URL | Apple Events per browser | Accessibility web area attribute | Removes the Automation prompt from onboarding |
| Semantic floor | None below the classifier | On-device contextual embeddings | Cheap pre-filter, and the fallback if the model is unavailable |
| Safety handling | Not considered | Guardrail violation treated as block evidence | The content that trips Apple's filter is the content we exist to catch |
| Full-URL network filter | Not considered | Evaluated and rejected | Requires a Private Information Retrieval server, which breaks the local-only rule |
| OS-level app shield | Implicitly hoped for | Documented as impossible on macOS | Screen Time frameworks are iOS-only; justifies the honesty clause |
