# Shift

Shift is a local app and website blocker for Apple Silicon Macs running macOS 26 or later. See the [product requirements](PRD.md) and [implementation status](PRD.md#16-milestones).

## Use a block

Create a block from **Blocks → New block**, then add websites, paths or apps. Choose **Always**, **Schedule**, or **None**. For **None**, right-click the block in the menu bar to start a timed run.

Save applies the edits in the block inspector. When breaks are enabled, choose “I need it” on the shield, enter a reason, and pick 2 or 5 minutes of access. Your choice starts a one-minute countdown. When it ends, you get the full 2 or 5 minutes on the matched site, path, or app. Each block allows two breaks per local day, counted when access starts. The shield waits 10, 20, or 30 seconds before showing the choices on repeat hits to the same rule within an hour.

Active website, path and app rules trigger the full-screen pause. Optional drift hints use keywords in the foreground window title.

## Permissions

Accessibility lets Shift read window titles and browser addresses and enforce the shield. When the permission is missing, the Dashboard shows how to grant it.

## Code-only verification

Run `./Tools/run-block-tests.sh` for the existing schedule and lock checks. To type-check the Swift sources for macOS 26 without producing or launching the app, run the following from the repository root.

```sh
rg --files Shift -g '*.swift' -0 |
  xargs -0 swiftc -typecheck -swift-version 5 -strict-concurrency=complete -target arm64-apple-macosx26.0
```
