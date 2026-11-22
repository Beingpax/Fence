# Shift

Shift is a local app and website blocker for Apple Silicon Macs running macOS 26 or later. See the [product requirements](PRD.md) and [implementation status](PRD.md#16-milestones).

## Use a block

Create a block from **Blocks → New block**, then add websites, paths or apps. Choose **Always**, **Schedule**, or **None**. For **None**, right-click the block in Blocks or the menu bar to start a timed run.

A break pauses only that block for the selected length. The daily allowance is the number of breaks you can start before local midnight. The shield automatically escalates from Gentle to Firm to Severe for repeat hits on the same rule or target, with a fresh count each local day.

An optional **Focus goal** enables intent detection. Explicit rules take priority. For unresolved screens, Shift reads accessible text and can use Vision to read a snapshot of the foreground window. Apple Intelligence judges the text on-device where available. **What Shift sees** shows the latest context, verdict and evidence source.

## Permissions

| Permission | Used for |
|---|---|
| Accessibility | Window titles, browser addresses and page text |
| Screen Recording | Optional, single-window screenshots for text recognition |
| Automation | Closing a tab in a browser with Apple Events support |

Shift keeps sampled images and page text in memory. Settings → Detection offers an optional comparison of the two text readers. The local system log collects sample IDs, durations, character counts and verdict categories.

## Code-only verification

Run `./Tools/run-block-tests.sh` for the existing schedule and lock checks. To type-check the Swift sources for macOS 26 without producing or launching the app, run the following from the repository root.

```sh
rg --files Shift -g '*.swift' -0 |
  xargs -0 swiftc -typecheck -swift-version 5 -strict-concurrency=complete -target arm64-apple-macosx26.0
```
