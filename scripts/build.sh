#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/MiBuds.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MiBudsMac" "$APP/Contents/MacOS/MiBudsMac"
cp -R "$BIN_DIR/MiBudsMac_MiBudsMac.bundle" "$APP/Contents/Resources/"
cp -R LICENSE LICENSES CREDITS.md "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/Source"
cp -R Sources Tests scripts packaging Package.swift .swift-format README.md LICENSE LICENSES CREDITS.md "$APP/Contents/Resources/Source/"
cp packaging/Info.plist "$APP/Contents/Info.plist"
if [ -f packaging/MiBuds.icns ]; then cp packaging/MiBuds.icns "$APP/Contents/Resources/"; fi
codesign --force --sign - --identifier local.mibuds.mac "$APP"
printf 'Built %s\n' "$APP"
