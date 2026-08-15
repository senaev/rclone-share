#!/usr/bin/env bash
# Assert the built app really contains a valid, signed share-services extension.
# This guards the one property the whole project depends on.
set -euo pipefail

APP="${1:?usage: verify.sh <path to .app>}"
APPEX="$APP/Contents/PlugIns/ShareExtension.appex"

if [ ! -d "$APPEX" ]; then
    echo "FAIL: $APPEX is missing"
    exit 1
fi

codesign --verify --deep --strict "$APP"
echo "ok: signature verifies"

POINT=$(/usr/libexec/PlistBuddy \
    -c "Print :NSExtension:NSExtensionPointIdentifier" \
    "$APPEX/Contents/Info.plist")

if [ "$POINT" != "com.apple.share-services" ]; then
    echo "FAIL: extension point is '$POINT', expected 'com.apple.share-services'"
    exit 1
fi
echo "ok: extension point = $POINT"

SANDBOX=$(codesign -d --entitlements - --xml "$APPEX" 2>/dev/null \
    | grep -c "com.apple.security.app-sandbox" || true)

if [ "$SANDBOX" -eq 0 ]; then
    echo "FAIL: the .appex is not sandboxed; macOS will refuse to load it"
    exit 1
fi
echo "ok: .appex is sandboxed"
