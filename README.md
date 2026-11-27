# Fence

Fence is a local app and website blocker for Apple Silicon Macs running macOS 26 or later. See the [product requirements](PRD.md) and [implementation status](PRD.md#16-milestones).

## Use a block

Create a block from **Blocks → New block**, then add websites, paths or apps. Choose **Always**, **Schedule**, or **None**. For **None**, right-click the block in the menu bar to start a timed run.

Save applies the edits in the block inspector. On any block, choose “I need it” on the pause, write at least 20 words about why, and pick 2 or 5 minutes of access. Your choice starts a 15-second countdown. When it ends, you get the full 2 or 5 minutes on the matched site, path, or app; the rest of the block stays on. When a blocked site or app comes up, a card gives you ten seconds to close it yourself; closing it then counts as turning back, with no pause. Still open after ten seconds, the screen pauses. Every pause is the same: one five-second breath, then “What’s pulling you here?” Pick an answer, add a few words if you like, and the tab closes or the app quits. Every pause and its words are kept on the Journal page.

Active website, path and app rules trigger the full-screen pause. Optional drift hints use keywords in the foreground window title.

### Quitting and startup

While a block is running or locked, Fence refuses ordinary Quit. You can switch off an unlocked block in the dashboard. A separate macOS login agent monitors enabled rules and presents the pause, including when the dashboard is force-quit. The dashboard stays closed after Force Quit. If the background agent exits, macOS restarts the approved agent and it reloads the saved rules. If neither process is running, blocking resumes when the agent starts; repeated exits can delay that restart. Background enforcement needs permission in **System Settings → General → Login Items & Extensions**. While approval is pending, the dashboard enforces blocks for as long as it is running.

Enabled schedules resume at sign-in. To start the menu bar app at every sign-in, including when all blocks are off, turn on **Settings → Startup → Open Fence at login**.

### Administrator-controlled installation

## Release and development builds

The two configurations are separate apps that never share anything:

| | Release | Debug |
|---|---|---|
| Name | Fence | Fence Dev |
| Bundle ID | `com.prakashjoshipax.Fence` | `com.prakashjoshipax.Fence.dev` |
| Data | `~/Library/Application Support/com.prakashjoshipax.Fence` | `~/Library/Application Support/com.prakashjoshipax.Fence.dev` |
| Background helper | `com.prakashjoshipax.Fence.enforcement` | `com.prakashjoshipax.Fence.dev.enforcement` |

Settings (UserDefaults), the Accessibility grant, logs and the messages between the app and its helper follow the bundle ID too, so each build asks for its permissions once. Each build starts with its own empty data folder.

To require administrator credentials for ordinary removal, build the installer from a current Fence.app and install the package in the standard system Applications folder. Use a standard macOS account for everyday use and keep the administrator credentials separate.

```sh
./Tools/package-fence.sh /path/to/Fence.app /path/to/Fence.pkg
```

The package installs a root-owned `/Applications/Fence.app`. With the default Applications folder permissions, a standard account needs administrator authorization to move or replace that copy, including during unlocked blocks. This protection applies whenever the package is installed. Administrators retain the ability to uninstall it. A copy launched from Downloads or a development build directory does not gain this protection. The command produces an unsigned installer for local use.

While a block is running or locked, the app and its background agent can put the running copy of Fence back if it is moved to the Trash. Recovery requires a running process, access to the trashed bundle, and permission to move it back to its original location. An occupied destination, an emptied Trash, or administrator removal can prevent recovery.

To remove Fence, open **Settings → Setup → Uninstall Fence**. When no block is running or locked, Fence can turn off its login items, quit, and select the installed app in Finder. Move it to the Trash to finish. Closing the Fence window keeps the app installed and blocking continues. If you cancel removal after Fence quits, reopen it to resume enabled schedules and re-enable Open at Login if desired.

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

Flip the Websites field's switch from **Block** to **Allow** to let a site, page or pattern through that block's website rules, pre-made lists included. For example, turn on Social media and allow `youtube.com/watch` to keep single videos open. Allowed entries show under **Always allowed**. Other active blocks and app rules still apply. A locked block allows removing allowed entries and adding blocked ones, but not allowing new ones.

## Adult site blocking

Choose **18+ sites** under **Websites → Common distractions** to add it to a block. While that block is active, Fence closes the tab on any page whose address or title has an explicit word or phrase in it, searches included, and on a short list of the most visited 18+ sites. Some words match anywhere, even inside a site's name (`freepornvids.net`); words that also have ordinary meanings match only as part of a phrase (`teen sex`, never `teen` alone), so pages like `sussex.ac.uk` or news about same-sex marriage stay open. A page that also has a word like *quit*, *addiction*, *health*, *news* or *meaning* in it is never closed by words, so `how to quit porn` and `what does NSFW mean` stay open; the known sites are closed regardless. The list's built-in sites and words are hidden and can't be searched or removed. You can add your own under the list's **Words** and **Websites** tabs.

Detection depends on a supported foreground browser exposing the address and title through macOS Accessibility. A page can begin loading before the tab closes. Searches sent privately in a request body and explicit images on otherwise unmarked pages are outside the filter's coverage. [Credits](CREDITS.md#adult-domain-catalog)

## Permissions

Onboarding requires **Background blocking**. Fence registers its helper directly. If macOS asks for approval, **Open Login Items** takes you to **Login Items & Extensions**, where you can enable Fence under **App Background Activity**. Once set up, the helper stays registered even when all blocks are off.

Fence uses browser access to read the active page and send the shortcut that closes a blocked tab. You can set it up in Fence under **Settings → Permissions** or during onboarding. In **System Settings → Privacy & Security**, the permission appears as **Accessibility** on macOS 26, **Device Control and Data Access** on 27.0–27.2, and **System & App Protection Override** on 27.3 and later. If macOS offers **Choose Apps**, select the browsers you want Fence to block. Reading a page and sending a shortcut are separate system checks.

## Code-only verification

Run `./Tools/run-block-tests.sh` for the fast schedule, lock and storage checks. To exercise Force Quit and recovery under macOS launchd, run the following from a logged-in Mac account.

```sh
python3 Tools/EnforcementLifecycleTests/test_enforcement_lifecycle.py
```

The lifecycle suite runs Fence’s engine in a temporary bundle with an isolated rule store and service name. It supplies app and browser samples in code and records pause requests without displaying windows. It unloads each temporary job after the test.

To type-check the Swift sources for macOS 26 without producing or launching the app, run the following from the repository root.

```sh
rg --files Fence -g '*.swift' -0 |
  xargs -0 swiftc -typecheck -swift-version 5 -strict-concurrency=complete -target arm64-apple-macosx26.0
```
