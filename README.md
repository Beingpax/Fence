# Shift

Shift is a local app and website blocker for Apple Silicon Macs running macOS 26 or later. See the [product requirements](PRD.md) and [implementation status](PRD.md#16-milestones).

## Use a block

Create a block from **Blocks → New block**, then add websites, paths or apps. Choose **Always**, **Schedule**, or **None**. For **None**, right-click the block in the menu bar to start a timed run.

Save applies the edits in the block inspector. When breaks are enabled, choose “I need it” on the shield, enter a reason, and pick 2 or 5 minutes of access. Your choice starts a one-minute countdown. When it ends, you get the full 2 or 5 minutes on the matched site, path, or app. Each block allows two breaks per local day, counted when access starts. The shield waits 10, 20, or 30 seconds before showing the choices on repeat hits to the same rule within an hour.

Active website, path and app rules trigger the full-screen pause. Optional drift hints use keywords in the foreground window title.

### Quitting and startup

While a block is running or locked, Shift refuses ordinary Quit. You can switch off an unlocked block in the dashboard. A separate macOS login agent monitors enabled rules and presents the pause, including when the dashboard is force-quit. The dashboard stays closed after Force Quit. If the background agent exits, macOS restarts the approved agent and it reloads the saved rules. If neither process is running, blocking resumes when the agent starts; repeated exits can delay that restart. Background enforcement needs permission in **System Settings → General → Login Items & Extensions**. While approval is pending, the dashboard enforces blocks for as long as it is running.

Enabled schedules resume at sign-in. To start the menu bar app at every sign-in, including when all blocks are off, turn on **Settings → Startup → Open Shift at login**.

### Administrator-controlled installation

To require administrator credentials for ordinary removal, build the installer from a current Shift.app and install the package in the standard system Applications folder. Use a standard macOS account for everyday use and keep the administrator credentials separate.

```sh
./Tools/package-shift.sh /path/to/Shift.app /path/to/Shift.pkg
```

The package installs a root-owned `/Applications/Shift.app`. With the default Applications folder permissions, a standard account needs administrator authorization to move or replace that copy, including during unlocked blocks. This protection applies whenever the package is installed. Administrators retain the ability to uninstall it. A copy launched from Downloads or a development build directory does not gain this protection. The command produces an unsigned installer for local use.

While a block is running or locked, the app and its background agent can put the running copy of Shift back if it is moved to the Trash. Recovery requires a running process, access to the trashed bundle, and permission to move it back to its original location. An occupied destination, an emptied Trash, or administrator removal can prevent recovery.

To remove Shift, open **Settings → Setup → Uninstall Shift**. When no block is running or locked, Shift can turn off its login items, quit, and select the installed app in Finder. Move it to the Trash to finish. Closing the Shift window keeps the app installed and blocking continues. If you cancel removal after Shift quits, reopen it to resume enabled schedules and re-enable Open at Login if desired.

## Website rules

Under **Websites**, enter one rule and press Return or Add. A domain or site path shows the pause screen. A word, phrase or URL pattern closes the matching foreground tab automatically. For a single-word hostname, include the scheme, as in `https://intranet`. The info button beside Websites explains the syntax. Save and enable the block to apply the rules.

| URL rule | Matches |
| --- | --- |
| `*concerts*` | An address containing `concerts` anywhere |
| `live scores` | The phrase anywhere in the address, including `?q=live+scores` |
| `/shorts/*` | An address containing `/shorts/` |
| `?q=*concerts` | A literal `?q=` followed anywhere later by `concerts` |

Matching ignores letter case. An asterisk matches zero or more characters. Question marks and slashes are literal. Previously saved search-only rules keep their search scope.

Choose **Pre-made lists** to add a category to the block. The picker shows its site count. The 11 general-purpose starter lists cover dating, distractions, email, gambling, games, news, proxies, search engines, shopping, social media and videos. A list matches its named hosts and their `www.` aliases. All 12 lists share one bundled JSON catalog.

Switch to **Website exceptions** to allow a domain, path, URL pattern or pre-made list through that block’s website rules. For example, add Videos under Websites and `youtube.com/learning` under Website exceptions to allow that section. Other active blocks and app rules still apply. A locked block allows removing exceptions and adding blocked lists.

## Adult site blocking

Choose **Websites → Pre-made lists → Adult sites** to add the category. Remove its chip to turn it off. New blocks start with no categories selected. Previously enabled adult filters carry over as selected categories. While a block with Adult sites selected is active, Shift closes sites listed by two sources and exact explicit searches on recognized results pages. The offline catalog includes exceptions for shared hosting and recognized government and education namespaces. A search for `NSFW` qualifies on a supported search page. A search for `what does NSFW mean` stays open under this filter.

Detection depends on a supported foreground browser exposing the address through macOS Accessibility. A page can begin loading before the tab closes. Searches sent privately in a request body and explicit images on otherwise unmarked pages are outside the filter’s coverage. The catalog ships as a snapshot. To regenerate it from the pinned source, run `python3 Tools/build-adult-catalog.py`. [Catalog credits](CREDITS.md#adult-domain-catalog)

## Permissions

Accessibility lets Shift read window titles and browser addresses and enforce the shield. When the permission is missing, the Dashboard shows how to grant it.

## Code-only verification

Run `./Tools/run-block-tests.sh` for the fast schedule, lock and storage checks. To exercise Force Quit and recovery under macOS launchd, run the following from a logged-in Mac account.

```sh
python3 Tools/EnforcementLifecycleTests/test_enforcement_lifecycle.py
```

The lifecycle suite runs Shift’s engine in a temporary bundle with an isolated rule store and service name. It supplies app and browser samples in code and records pause requests without displaying windows. It unloads each temporary job after the test.

To type-check the Swift sources for macOS 26 without producing or launching the app, run the following from the repository root.

```sh
rg --files Shift -g '*.swift' -0 |
  xargs -0 swiftc -typecheck -swift-version 5 -strict-concurrency=complete -target arm64-apple-macosx26.0
```
