#!/usr/bin/env bash
# Wrap the .app into a DMG named after its version.
set -euo pipefail

APP="${1:?usage: package.sh <path to .app>}"

VERSION=$(/usr/libexec/PlistBuddy \
    -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="RcloneShare-${VERSION}.dmg"

if [ -f "$DMG" ]; then
    rm "$DMG"
fi

# create-dmg exits non-zero when it cannot sign the image, which is expected
# for ad-hoc builds. Check for the output file instead of trusting the code.
create-dmg \
    --volname "RcloneShare $VERSION" \
    --window-size 620 380 \
    --icon-size 96 \
    --app-drop-link 420 180 \
    "$DMG" "$APP" || true

if [ ! -f "$DMG" ]; then
    echo "FAIL: $DMG was not produced"
    exit 1
fi

echo "packaged: $DMG"
