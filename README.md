# Shift

Shift is a local app and website blocker for Apple Silicon Macs running macOS 26 or later. See the [product requirements](PRD.md) and [implementation status](PRD.md#16-milestones).

## Use a block

Create a block from **Blocks → New block**, then add websites, paths or apps. Choose **Always**, **Schedule**, or **None**. For **None**, right-click the block in the menu bar to start a timed run.

Save applies the edits in the block inspector. When breaks are enabled, the shield offers up to two two-minute pauses for that block each local day. The shield automatically escalates from Gentle to Firm to Severe for repeat hits on the same rule or target, with a fresh count each local day.

Active website, path and app rules trigger the shield. Add an optional **Focus goal** to get gentle reminders during sustained distraction. Apple Intelligence classifies foreground text on this Mac. **What Shift sees** shows the latest context and decision.

## Permissions

Accessibility lets Shift read window titles and browser addresses and enforce the shield. When the permission is missing, the Dashboard shows how to grant it.

Optional **Screen Recording** permission in Settings lets Shift read a snapshot of the frontmost window when Accessibility exposes too little text. Captured images and text stay in memory for the sample.

## Code-only verification

Run `./Tools/run-block-tests.sh` for the existing schedule and lock checks. To type-check the Swift sources for macOS 26 without producing or launching the app, run the following from the repository root.

```sh
rg --files Shift -g '*.swift' -0 |
  xargs -0 swiftc -typecheck -swift-version 5 -strict-concurrency=complete -target arm64-apple-macosx26.0
```
