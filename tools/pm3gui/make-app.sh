#!/bin/bash
# Wrap the SwiftPM executable in a real .app bundle.
#
# Running the bare binary mostly works, but an unbundled process has no bundle
# identity, and AppKit's AutoFill heuristics crash (SIGTRAP inside
# SPSafariPlatformSupport) when they try to offer a one-time-code popup over the
# Tag ID field. A proper bundle also gets a Dock icon and normal activation.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-debug}"
APP="build/PM3GUI.app"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp ".build/$CONFIG/PM3GUI" "$APP/Contents/MacOS/PM3GUI"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>PM3GUI</string>
    <key>CFBundleDisplayName</key>
    <string>Proxmark3 LF Tags</string>
    <key>CFBundleIdentifier</key>
    <string>org.proxmark3.pm3gui</string>
    <key>CFBundleExecutable</key>
    <string>PM3GUI</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: unsigned bundles get less consistent treatment from AppKit,
# and this costs nothing.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
