#!/bin/bash
set -euo pipefail

if [[ $# != 2 ]]; then
    echo 'Usage: package-fence.sh /path/to/Fence.app /path/to/Fence.pkg' >&2
    exit 2
fi

app=$1
output=$2
info="$app/Contents/Info.plist"
agent="$app/Contents/Library/LaunchAgents/com.prakashjoshipax.Fence.enforcement.plist"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")" != com.prakashjoshipax.Fence ||
      ! -x "$app/Contents/MacOS/Fence" || ! -f "$agent" ]]; then
    echo 'Expected a Release build of Fence with the embedded background agent.' >&2
    exit 1
fi
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/payload"
/usr/bin/ditto --noacl "$app" "$stage/payload/Fence.app"
/bin/chmod -RP go-w "$stage/payload/Fence.app"
components="$stage/components.plist"
/usr/bin/pkgbuild --analyze --root "$stage/payload" "$components"
# Keep the machine-wide install at /Applications even if a user has a second copy.
[[ "$(/usr/libexec/PlistBuddy -c 'Print :0:RootRelativeBundlePath' "$components")" == Fence.app ]]
/usr/bin/plutil -replace 0.BundleIsRelocatable -bool false "$components"

/usr/bin/pkgbuild --root "$stage/payload" --component-plist "$components" \
    --install-location /Applications --ownership recommended \
    --identifier com.prakashjoshipax.Fence.pkg --version "$version" "$output"
