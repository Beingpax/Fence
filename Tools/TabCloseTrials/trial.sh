#!/bin/bash
# Real-browser check that "Close the tab" closes exactly the blocked tab.
#
#   ./Tools/TabCloseTrials/trial.sh "Google Chrome" https://x.com 3
#
# Needs a Debug build (Fence Dev) running with a block on that lists the site. Opens the site, waits
# for the pause, presses Close through the Debug-only `debugPauseClose` hook, then prints
# TabCloser's log and whether the pause came back. Open a safe page first
# (`open -a "<browser>" https://example.com`) so the window has another tab to land on:
# "verify: now showing example.com" is the proof that one tab, and only that one, closed.
set -u
cd "$(dirname "$0")"
POST="${TMPDIR:-/tmp}/fence-post"
[ -x "$POST" ] || swiftc -O -o "$POST" post.swift
ID=com.prakashjoshipax.Fence.dev
DB="$HOME/Library/Application Support/$ID/journal.sqlite"
app="$1"; url="$2"; delay="${3:-3}"
mark=$(date +%s); since=$(date "+%Y-%m-%d %H:%M:%S")
count() { sqlite3 "$DB" "select count(*) from reaches where started_at >= $mark"; }
open -a "$app" "$url"
for _ in $(seq 1 60); do [ "$(count)" -ge 1 ] && break; sleep 0.25; done
if [ "$(count)" -lt 1 ]; then echo "RESULT $app $url: no pause within 15 s"; exit 1; fi
sleep "$delay"
"$POST" "$ID.debugPauseClose"
sleep 9
log show --start "$since" --info --predicate "subsystem == \"$ID\" && category == \"TabCloser\"" --style compact | tail -n +2
if [ "$(count)" -eq 1 ]; then echo "RESULT $app $url close@${delay}s: no second pause"; else echo "RESULT $app $url close@${delay}s: paused again ($(count))"; exit 1; fi
