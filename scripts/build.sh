#!/usr/bin/env bash
# Build RcloneShare.app (Release, ad-hoc signed) into build/out/.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d RcloneShare.xcodeproj ]; then
    xcodegen generate
fi

xcodebuild \
    -project RcloneShare.xcodeproj \
    -scheme RcloneShare \
    -configuration Release \
    -derivedDataPath build \
    CONFIGURATION_BUILD_DIR="$PWD/build/out" \
    build

echo "built: build/out/RcloneShare.app"
