#!/usr/bin/env bash
# Install the locally built app to /Applications, register it, and launch it.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/out/RcloneShare.app"
DEST="/Applications/RcloneShare.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

if [ ! -d "$APP" ]; then
    echo "FAIL: $APP not found. Run scripts/build.sh first."
    exit 1
fi

if pgrep -f "$DEST/Contents/MacOS/RcloneShare" >/dev/null 2>&1; then
    osascript -e 'quit app "RcloneShare"' || true
    sleep 1
fi

if [ -d "$DEST" ]; then
    rm -r "$DEST"
fi

cp -R "$APP" /Applications/
"$LSREGISTER" -f "$DEST"
open "$DEST"

sleep 3
echo "=== registered share-services providers matching rclone-share:"
pluginkit -mAvv -p com.apple.share-services 2>/dev/null | grep -A5 "rclone-share" \
    || echo "WARNING: not registered yet"
