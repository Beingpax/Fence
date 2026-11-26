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
  **It must shrink as well as grow** (fixed 26 Nov 2026): `DayStage` measures its own
  width, so nothing inside it may take a width worked out from that measurement. Lanes and
  the axis are flexible frames, segments ride in an overlay, and the stage's frame has
  `minWidth: 0`. Before this the card widened with the window and then held that width,
  clipping the switches. The fact pills wrap below the legend when one row doesn't fit.
- **The main window's minimum is 860 × 580** (`Theme.mainWindowMinSize`), set once as the
  window's `contentMinSize` and the SwiftUI root's min frame. The two used to disagree
  (820 vs 900), and the hosting view clipped the sidebar and content on both sides.
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
- **Every pause is journaled, and the way back needs a few written words** (26 Nov 2026,
  the user's call). `ReachJournal` (`Models/ReachJournal.swift`) writes each reach to SQLite
  at `~/Library/Application Support/Shift/journal.sqlite`: time, local day, hour, block,
  rule, site or app, URL, window title, visit number, the feeling, what they wrote, and the
  outcome (`closed`, `break` for "I need it" access, `dismissed`, `left_early`, `open`). The schema is plain so it can be queried
  from a terminal later; the `daily` view sums each day. Both processes write to it (WAL
  mode). The pause is one version every time (see "The pause"): Close isn't offered until
  an answer is picked and `UrgeReason.minimumWords` are written, 10 for a feeling and 20
  for "I need it". The **Journal** sidebar
  section (`UI/Main/JournalView.swift`, teal tile) shows two weeks of "pulls" as bars, a few
  fact pills and one summary card per day showing **only where and why** (pills, most
  frequent first): no pull count, no turned-back count, no counts on the pills and no hour
  strip (26 Nov 2026, the user's call). No
  per-pull list: the user found it read like a log file (26 Nov 2026); every pull, its time
  and its words stay in `journal.sqlite` for analysis. Information, never a grade:
  no streaks or scores. Researched in `Research/habit-science-review.md`. The user rejected
  two ideas from that review: a "Back to work" button after closing, and if-then plans in
  the person's own words. Don't add either without asking. Not yet built or seen running.
- **The sidebar is Shift's own and stays exactly as on `main`** (26 Nov 2026, the user's
  call after it was changed twice): a Liquid Glass panel (`.glassEffect(.regular)`) pinned to
  the window's leading edge, full height, with only its trailing corners rounded; the
  selected row uses `unemphasizedSelectedContentBackgroundColor`; section tiles are system
  orange, indigo, teal (Journal) and gray; the count badge is the accent colour. It is an exception to the
  palette rules. Don't flatten it to cream, swap it for `NSVisualEffectView` materials, or
  float it inset like the system sidebar.
- **The block editor was redesigned on 26 Nov 2026** (the user found it "too bad" and asked
  for a complete redesign: bold, playful, clean, easy, macOS 26 glass). Still the trailing
  sliding panel (now 440 wide), one column in the order people think: a 60 pt badge (click
  it for a colour and icon popover) beside a big name field with a coral small-caps eyebrow
  (focused for a new block); a lock banner with Unlock when locked; then titled sections on
  frosted white cards (`EditorSection`, `editorCard()`): **Websites** (the add field, then
  the pre-made lists as pills, then the block's own sites as chips, then Import and an
  "Always allow" disclosure for single pages), **Apps** (chips with icons, "Choose apps"),
  **When it's on** and **Lock**. Since 26 Nov 2026 at the user's request: **no Quick add**;
  **sites and apps are chips** (`ChipCloud`, `EntryChip`), several to a line, never one per
  row; When is a wrapping row of `ModePill`s **drawn exactly like the pre-made list pills**
  (solid coral once chosen, soft tile otherwise); **Lock is one row that opens Shift's own
  picker** (`LockPicker`, a popover of five `LockOptionRow`s, each a tile, a title and one
  short line), not every method laid out at once. Their settings follow as solid
  `ChoicePill`s on one line (`InlineChoices`, a compact `UntilTimeChooser`), with **no
  description lines** in the card: When's tooltips explain each choice. Schedule windows sit
  on one line of small day letters and time pills, with a "+1" badge for overnight.
  **Import** (`ListImport`) reads a .txt (one entry per line, `#` comments, hosts files) or a
  .json (`["a.com"]` or `{"sites": [...], "apps": [...]}`), up to 5,000 entries; the ? beside
  it shows both formats as examples. **Glass only on
  controls**: the floating close circle and the Cancel / Create Block (Save) buttons
  (`.glass`, `.glassProminent` tinted coral, ⌘S, Esc). Coral marks selection; the block's
  colour appears only on its badge. The app picker sheet matches. `usesGlassCards` and
  `LockMethodPicker` were removed with the old editor. The add field's leading button is
  the same coral circle as "Choose apps" (`RuleInput`). **Help popovers are examples first**
  (`HelpCard`, `HelpExample`, `HelpFile`): "youtube.com → The whole site", a sample file,
  a few plain words each, never paragraphs of rules; tooltips likewise name examples
  ("Instagram, TikTok, YouTube, Netflix and other feeds"). The until-time lock reads in
  order: "Until", the time in a stepper with today/tomorrow beside it, then smaller
  outlined `QuickPick`s under it. **The typing-code unlock**
  (`RandomStringUnlockView`) was redesigned the same day, after the user rejected the tile
  grid: the code is one card of text in groups of four that you type straight into (done
  characters fade, the next is underlined in coral, a wrong one turns red at once), a bar
  that turns mint when it's right, and Unlock only then. Not yet built or seen running.
- **Pre-made lists are their own thing** (26 Nov 2026, the user's call), labelled **Common
  distractions** in the editor (the code still says pre-made). Four lists,
  `PreMadeList` in `Intelligence/WebsiteCategoryCatalog.swift`: Social media (social, chat,
  YouTube and every video and streaming site: **feeds only, never chat apps**, so no
  Discord, WhatsApp, Telegram, Messenger or Viber), News (about 270 big sites, weighted to
  the US and Germany, plus Nepal, India, the UK, Canada, Australia and more), Email, and
  **18+ sites** (never "adult
  sites" in the UI; saved as "Adult sites", the old key). Search engines, proxies, games,
  gambling, shopping, dating, videos and "Distractions" were removed; old saves fold Videos
  and Distractions into Social media and drop the rest (`PreMadeList.migrate`). **Each list
  carries Mac apps too** (`builtInApps`, iOS bundle IDs for iPhone apps on the Mac), blocked
  when installed. In the Websites card each list is a `ListPill`: the name puts it in the
  block, the sliders open `PreMadeListEditor`: a search field, Websites / Apps, an add field
  and Import, and everything as chips (the user's additions in soft coral). **Edits are to the
  list itself**, saved as differences from the bundle in `Application Support/Shift/lists.json`
  by `PreMadeLists`, which the helper rereads within a second. While a locked block uses a
  list, it can only grow. **Lists can never be allowed**: "Always allow" takes single pages
  and patterns only, and `exceptionCategoryNames` is gone (ignored when decoding). Not yet
  built or seen running.
- **No description lines under titles** in Settings and the Dashboard (26 Nov 2026, the
  user's call). Rows, sections and tiles show their title only; any explanation moves to a
  hover tooltip (`.help`). Exceptions: a permission that still needs fixing keeps its one
  instruction line; the How blocking works steps are the content itself; the Dashboard's
  live status line under the greeting stays. Onboarding keeps its subtitles; it's a
  guided first run.
- Shared page pieces (`PlayHero`, `PlaySection`, `PlayRhythm`, `RowDivider`, `SwitchLine`,
  `ActionLine`, `PermissionLine`, `SoftPillButtonStyle`) are in `UI/Design/Playful.swift`.
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
- Test without side effects: Settings → Previews has the pause (one button: it's the same every time), the turning-back reward, and the soft drift hint. Settings → How blocking works, the onboarding demo page and the README describe the same flow: change them together with the pause.
- Real test: switch on a block listing `instagram.com` or `youtube.com/shorts`, then open it in Safari or Chrome. The pause should cover the screen within about a quarter of a second of pressing Return, usually before the page has loaded.
- Shift requests Accessibility for window titles and browser addresses.
- **Signing is load-bearing for permissions.** `DEVELOPMENT_TEAM = V6J6A3VWY2` is set on both configurations, so builds are signed with a real identity. Do not let this fall back to ad-hoc. macOS keys TCC grants to the designated requirement, and an ad-hoc signature puts the binary's `cdhash` in that requirement, so **every rebuild silently voids the Accessibility grant** and the app reports "not granted" while System Settings still shows it enabled. Verify with `codesign -d -r- <app>`: the requirement must name the certificate, not a `cdhash`. If a grant ever does go stale, `tccutil reset Accessibility com.beingpax.Shift` and grant it again.
- **Real pauses come from the background helper, not the app Xcode runs.** The
  `--enforcement-agent` process is a `KeepAlive` launch agent that owns the monitor, so
  after a rebuild it kept enforcing with the old code for hours (26 Nov 2026: previews showed
  the new pause, real pauses the old one, and the journal stayed empty). It now restarts
  itself: `AppModel.restartIfReplaced` compares `ExecutableStamp` (inode, size, modification
  date) every 5 s and exits once the new executable has been stable for 4 s, with no pause
  on screen and no "I need it" access running; launchd relaunches it on the new build. To
  restart it by hand: `launchctl kickstart -k gui/$UID/com.beingpax.Shift.enforcement`.
  The dashboard also checks the helper (`replaceStaleHelper`): one running another copy of
  Shift (Xcode's build folder against /Applications) or started before this copy was built
  is asked to restart (`restartHelper` notification), and re-registered from this copy if
  it's still stale 20 s later. The dashboard relaunches itself after an update too
  (`relaunchDashboard`), but only while none of its windows is open; the relaunch passes
  `--relaunched-after-update` so it comes back without opening a window. Xcode's debugger
  holds a stopped app as "traced": kill the `debugserver` parent, not the app.
- Automated GUI testing needs Accessibility and Screen Recording granted to the terminal running Claude Code. Without them, `osascript` UI scripting fails with -1719 and `screencapture` fails outright, so shield verification has to be manual.

## Verification checklist (not yet walked through by hand)

1. **Menu bar.** Icon appears; the count next to it matches the number of active blocks.
2. **Main window.** Menu bar → Open Shift. Create a block, add sites and apps, save.
3. **Blocking.** Switch the block on, visit a listed site in Safari and Chrome. The
   heads-up card (annoyed mascot) should appear almost at once and the page stays usable.
   A click or a two-finger swipe dismisses the card but not the countdown. Close the tab
   within 10 s yourself: a reward, a
   "Before the pause" row in the Journal, no pause. Stay 10 s: the pause should cover
   every display. Come back within 2 minutes of leaving: straight to the pause. After one 5 s breath the six answers
   appear; there is no Close yet. Pick a feeling, write 10 words, and Close appears (Return
   works too); it closes only the tab, then shows the reward. The back button in the
   panel's top-right corner returns to the answers. Each pause should appear on the Journal
   page and in `journal.sqlite`. "I need it" is always there: write 20 words, pick 2 or 5
   minutes, and wait 15 s for access to the matched rule. The countdown has no buttons. A
   repeat reach looks the same, with different words. Check the wallpaper matches the
   time of day.
4. **Schedules.** Set a window that starts a minute from now and confirm it self-activates.
5. **Nudges.** With a block active and nudges enabled, open an unblocked window whose title contains a configured feed keyword.
6. **Locks.** Each of duration, until-time, random-string and restart. Check that the
   switch, the editor and Delete all refuse while locked.
7. **I need it.** Take 2 minutes of access, confirm only that site opens, and that the
   pause comes back when the time is up.
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
- **No breaks setting.** The per-block breaks switch, its two a day and the "on a break"
  state were removed on 26 Nov 2026 (the user's call). "I need it" at the pause is always
  offered instead: 20 written words, a 15-second wait, then 2 or 5 minutes on the one
  matched rule (`AccessPlan`), with no daily limit. Old saves still carry a `breaks` key;
  decoding ignores it.

Several blocks can be active at once. `BlockEvaluator` asks each active block in order and
the first with an opinion wins. A block is active when it is enabled or locked on, is
inside its schedule.

Rules that are easy to get wrong, and are covered by the tests:

- Schedule windows may run past midnight; the window belongs to the day it started on.
- An `untilTime` lock set to a time already past today rolls to tomorrow.
- A `restart` lock releases after the boot session changes (`kern.bootsessionuuid`), and
  **the block stays on, unlocked** (26 Nov 2026, the user's call; before that a restart
  also switched it off, which with Until restart as the default would have turned every
  block off on every reboot). Saves without a session ID fall back to `kern.boottime`,
  never `now - systemUptime`: uptime stops during sleep, so a nap looked like a restart.
- **Lock order is No lock, Until restart, For a while, Until a time, Typing code**
  (`LockMethod`'s declaration order), and **new blocks default to Until restart**
  (`presentNewBlock`, onboarding's `lockChoice`). It engages only when switched on.
- While locked, a block may be edited only to become stricter. Entries can be added,
  and the schedule and lock method are frozen.
- **A blocked app outranks every page inside it**, across all active blocks: Arc on
  x.com, with Arc blocked anywhere, is an app match (quit Arc), not a website match (close
  the tab). Website rules are only looked at when no active block lists the app. Before
  26 Nov 2026 the website rule won, so Shift closed one tab and paused again on the next.
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
- `AddressObserver` holds repeated title changes to about two samples a second (26 Nov 2026):
  a terminal with a spinner in its title drove about ten full Accessibility reads a second.
  Focus, window and load-complete notifications still sample after 90 ms.
- Looping `TimelineView` animations (the mascot, onboarding's stars and dots) pause on
  `\.windowIsVisible` (`UI/Design/WindowVisibility.swift`), set by
  `.tracksWindowVisibility()` at the root of the main and onboarding windows. Onboarding's
  window is only ordered out on close, so before this its animations ran for the life of the
  process. Any new looping animation in a window should read it too.

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
    rest, teal when curious, amber when worried, deep red when annoyed, gold when proud,
    blue when sad, dim while "I need it" access runs.
  - **Thirteen of the sixteen study moods are in the app** (26 Nov 2026, the user's call,
    replacing "only the four the HUD uses"). `MascotMood` follows the study's table, ported
    from `Studies/mascot-compare.html` with its positions divided by 1.9 (the study's scene
    units): idle, hello, thinking, shy; curious, cheeky, worried, annoyed; happy, cheer,
    proud; resting, sad. **Sorry, laughing and hold on were removed the same day** because
    the user didn't like how they look: don't bring them back, or their shrug, shake, "!"
    and raised hands. Each mood brings its face, hand pose (grip, wave, fists, thumb, chin,
    tapping) and effects (?, sweat, a tear, steam, sparkles, zzz). **The mood follows the message, not the card type:** drift hints go
    curious, then cheeky, then worried as the same drift repeats within half an hour;
    rewards are happy, cheer or proud by the line (`PauseCopy.mood(for:)`: harder-set
    lines and lines about strength are proud, exuberant ones cheer); access starting is
    resting; something that didn't work, or "close the tab manually", is worried.
    Onboarding's welcome waves hello, the empty Blocks page is thinking, the Dashboard is
    idle (hello with no blocks, curious when a permission is missing). The heads-up card
    before the pause is annoyed, and sad from the third time in an hour. Shy is unused.
    Settings → Previews → "Mascot moods" plays them all on the live card, and "Mascot
    gallery" (`UI/MascotGallery.swift`, a sheet) shows every place the mascot appears with
    its real words and mood, side by side. The gallery draws nudges with
    `NudgeCardPreview`, which shares `NudgeMessage` with the live card, and in-app cards
    with `MascotCard`; reward examples come from `PauseCopy` through `PauseCopy.mood(for:)`.
    Its other example texts are copies: update them when that copy changes.
  - **It peeks over the card and holds its edge.** The view draws twice: `.body` behind the
    card, clipped at the card's top edge so it can rise from behind glass without showing
    through, and `.hands` in front of it. Both layers share one `start` date so they move on
    one clock. Hands are worked out as in the study's `peekHands`: each mood weight pulls
    them from their grip toward a pose.
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
    when you turn back) and `shield.m4a`, played by `playDeep()` (a calm deep chord). The
    deep chord marked the third reach until the ladder went on 26 Nov 2026; nothing plays it
    now, and every pause gets the same chime.
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
  one screen. It waited longer each time until 26 Nov 2026; now it's the same every time.
  See "The pause" below.
  - **A website rule closes the tab; an app rule quits the app, browsers included.**
    Quitting the whole browser for a website punished the wrong thing. But a block that
    lists the browser app itself (Arc) quits it, and the button says "Quit Arc"
    (`PauseRequest.closesTab`); until 26 Nov 2026 any browser got "Close the tab". Quitting
    never brings the app forward; if it's still open after 1.5 s it's probably asking
    something, so then it comes forward to be answered. Otherwise the next app gets focus,
    never Shift's own window.
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
- **An allowed helper can still be unloaded.** `launchctl bootout`, or launchd giving up on
  a crashing job, leaves `SMAppService.status == .enabled` with nothing running, and
  `register()` refuses a service that's already registered, so nothing brought it back and
  the row's "Open Login Items" led to a switch that was already on (26 Nov 2026, after a
  bootout during testing). `AppModel.repairHelperIfDue` now calls
  `EnforcementService.reload()` (unregister, then register) when a 15-second check finds it
  offline, at most every two minutes; the row's "Restart helper" does it straight away.
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
├── Models/         Block (+ BlockList, BlockSchedule, ScheduleWindow, BlockLock, AccessPlan,
│                   BlockTint), BlockStore (persistence, locking, CRUD),
│                   ScreenContext, Verdict, ActivityEvent, DistractionPreset,
│                   Urge (the reasons shown in the pause),
│                   ReachJournal (every pause, in SQLite, + Reflection word count),
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
readings, the second requested 150 ms after the first) → `reach` (the 10 s heads-up card;
leaving during it ends here, with praise) → `beginReach` → `PauseController` →
`handlePause` → close the tab and reward the user, or start temporary access.

### The pause
Every choice here comes from habit research. Check changes against these, and don't
relitigate them without asking:

- **Catch the cue, before the reward.** `AddressObserver` subscribes to the front app's
  Accessibility notifications (focused element, title, window, `AXLoadComplete`), so
  pressing Return wakes a sample within ~0.1 s. Value-changed is deliberately *not*
  observed: it fires on every keystroke in every text field. A feed that never pays out
  stops being worth reaching for, which is why speed matters more than anything else.
- **A heads-up first, then the pause** (26 Nov 2026, the user's call, made knowing the
  trade-off above). Detection is still instant, but what appears first is the nudge card
  (`AppModel.reach`, `PauseCopy.warning`): "x.com is on your Distractions list." and "Close
  the tab, or I'll step in." ("Quit the app…" for apps; kept short at the user's request),
  with no button, the annoyed mascot (sad from
  the third time in an hour) and the page left usable. The user wanted people to be able to
  turn back on their own before Shift steps in, and judged ten seconds of feed an
  acceptable price; I recommended hiding the page during the countdown and the user chose
  not to. A Close button on the card was tried and removed the same day: closing is the
  person's own act. Leaving within 10 s (Cmd-W, another page or another app, read twice
  150 ms apart; a browser showing no page, such as Safari's Start Page or a window closed
  with its last tab, once that has lasted 1 s) is a self-made turn back, praised the moment
  it's seen (`noteLeaving`; until 26 Nov 2026 a blank never counted, so praise only came
  when something else changed, 8 to 37 s late). Debug builds also listen for
  `debugCloseFrontTab` and `debugNewTab` (Cmd-W and Cmd-T to the front browser) for
  scripted trials. Verified: Cmd-W noticed about 0.3 s after, a blank tab at 1 s, and staying
  brings the pause at exactly 10 s. Leaving earns `PauseCopy.turnedBackEarly` praise and a `left_early` journal
  row. Still on it at 10 s: the pause. Coming back within 2 minutes of leaving, or hopping
  to another blocked target during the countdown, goes straight to the pause, so stepping
  away can't restart the clock. Settings → Previews → "Heads-up" shows the card.
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
  one breath, 5 s, every time (`PauseRequest.waitSeconds`), drained by one linear animation
  **from the right, anchored at its leading edge** (stepped once a second under Reduce
  Motion). It empties one way, like every other progress bar on the platform; pulling away
  from the middle in both directions at once was wrong and the user caught it. Digits invited
  counting; the bar is read at a glance and forgotten. The "Breathe in / and let it go"
  cue is gone with them at the user's request — the constellation already opens and
  gathers in time with the breath, and words only ask to be obeyed. Rejected on
  the way: rippling rings, a glass orb with orbiting motes, and several organic blobs
  (opaque, foggy, then a translucent drop the user hated). When it ends, the orb grows into the question panel
  (`matchedGeometryEffect`), the question reveals, and the answer chips arrive one after
  another: all six, in a 3 × 2 grid. **The question must be answerable by the chips.** It is "What's pulling you
  here?": the chips name a state ("I'm bored", "This is hard"), so the earlier "What were
  you hoping it would give you?" asked for a reward and left every answer reading like a
  non-sequitur. The question asks what prompted the reach. Each chip has a short label and
  a symbol, with a longer description on hover. Choosing a chip replaces the question with its
  answer, with a what, why or how prompt (`UrgeReason.prompt`) and a field that needs
  `UrgeReason.minimumWords` before anything moves on: 10 for a feeling, 20 for "I need it".
  The solid white close button sits outside the panel and is **not offered during the
  breath or the question** (the user's call, 26 Nov 2026, over keeping it always
  available); it fades in once the words are written, and Return in the field then closes.
  "Pick a different answer" returns to the chips. Sources: GOV.UK's
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
  bored, drained, this is hard, anxious, alone, I need it. Keep it to these six: "On
  autopilot", "Just checking" and "I'm waiting" were added and removed the same day
  (26 Nov 2026); the user finds the six cover it and doesn't want more options or
  categories.
- **Every answer closes it, except one.** Each craving gets a line on what would meet it
  better than the feed (a stretch, rest, a tiny step, writing it down, a real person),
  and the only button closes the tab once they've written why. The person does the better
  thing themselves; the user explicitly didn't want in-app timers for these. The one form is
  the written reason, which feeds the journal.
- **"I need it" opens one site, never the block.** It's always one of the six answers,
  asks what for in 20 words, then offers 2 or 5 minutes of access after a 15-second wait
  (`AccessPlan`). The countdown uses the same frosted panel and
  continuously draining bar as the pause. Closing the target during the wait cancels it.
  When access begins, it temporarily allows the matched rule (`AppModel.allow`, keyed by
  `reachKey`). When access expires, Shift reads the screen again and restores the pause
  if the current context is still blocked.
- **Never the same words twice in a row.** `PauseCopy` holds 64 pause headlines (by
  visit), 15 heads-up headlines and about 150 turning-back lines, dealt by `CopyDeck` so
  nothing repeats until the rest of its set has been seen. **Rewritten in full on
  26 Nov 2026** at the user's request; the rules are at the top of `PauseCopy.swift` (true to
  the moment, nothing made up, no scores or streaks, nothing assumes work, fits the card).
  Each turning-back line carries its own mascot mood (`PauseCopy.Reward`). Which set: after
  "I need it", `changedMind`; a repeat reach within the hour, `turnedBackAgain`; otherwise
  half the time the named feeling's set, half the general `turnedBack`; during the heads-up,
  `turnedBackEarly` (which says "moved on", since they may only have switched away). The
  user asked for many lines; add rather than trim, in that voice.
- **Reward turning back, immediately.** The mascot's happy face, a sparkle burst and the `reward` chime. This is the step that
  builds the habit; before it, turning back got nothing.
- **One version, every time.** The ladder (10, 20, 30 s waits and a deeper chime from the
  third reach) was removed on 26 Nov 2026: the user wanted one pause people can learn and
  trust. Reaches are still counted per block and target for an hour (`reaches`, keyed by
  `reachKey`), but only to pick warmer copy for a repeat; the flow doesn't change.
- **No shame, anywhere.** The voice is a friend's. The urge is "the pull", not the person.
- `Close it` closes the **tab** (`TabCloser.closeFrontTab`): it yields activation to the
  browser, then presses the browser's own menu item bound to Command-W through
  Accessibility (found by shortcut, so any language), falling back to Command-W posted to
  the browser's pid. It checks the page is still **blocked by a rule**, never that the URL is
  unchanged: the pause beats the page load, so `x.com` became `x.com/home` and the old
  exact-URL check left those tabs open (fixed 26 Nov 2026). It then reads the window again
  and retries with the other method only if it can see the same page still there, so it
  can't close a second tab; a window it can't read counts as closed (the monitor re-pauses
  if not). Two things the real-browser trials showed (26 Nov 2026): Safari ignores Close
  Tab sent the instant it becomes frontmost, so the browser must have been in front for
  300 ms first; and Chromium browsers return no URL after the pause unless the read asks
  for the tree again (`prepareAccessibility: browser.isChromium`). Verified in Safari,
  Chrome, Edge and Brave, while loading and after load: one tab closed, the next tab
  read back. `TabCloser` logs every step (category `TabCloser`). Repeat the trials with
  `./Tools/TabCloseTrials/trial.sh "<Browser>" https://x.com 3` against a Debug build,
  which listens for `debugPauseClose`. Firefox, Dia, Vivaldi and DuckDuckGo raised no pause
  at all in those trials: detection, not closing, and not yet investigated. Apps are asked
  to quit (`TabCloser.quit`).

**Every nudge card has one shape and no buttons** (26 Nov 2026, the user's call): the same
300 pt width, a one-line headline (shrinks a little, then truncates) and a detail that always
reserves two lines (`NudgeMessage`), so cards never change size. The hover × is gone: a
click anywhere on the card dismisses it, and so does a two-finger sideways swipe
(`NudgeHostingView` reads the trackpad's scroll events, which SwiftUI gestures don't see).
Keep headlines to about 35 characters and details to two lines.

`NudgeHUDController` serves five kinds: `hint` (soft drift), `reward` (after turning back),
`status` (something didn't work), `warning` (the heads-up before the pause, up for its full
10 s) and `access` ("I need it" running: "x.com is open" with a live countdown beside it and
their reason under it, resting mascot, up until the access ends; the user's call,
26 Nov 2026, so the end never comes as a surprise). Hints never cover a warning, a reward or
an access card. Every card can be clicked or swiped away early. `hideHint()` takes down only hints, so a
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
