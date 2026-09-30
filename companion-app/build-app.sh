#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST_DIR="${1:-$SCRIPT_DIR/dist}"
APP_DIR="$DEST_DIR/NahidaCompanion.app"

swift build --package-path "$SCRIPT_DIR" -c release
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$SCRIPT_DIR/.build/release/NahidaCompanion" "$APP_DIR/Contents/MacOS/NahidaCompanion"
cp "$ROOT_DIR/spritesheet.webp" "$APP_DIR/Contents/Resources/spritesheet.webp"
rm -rf "$APP_DIR/Contents/Resources/Voice"
VOICE_SOURCE_DIR="${NAHIDA_VOICE_DIR:-$ROOT_DIR/voice}"
if [[ -d "$VOICE_SOURCE_DIR" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources/Voice"
  for clip in greeting celebrate birthday \
    reminder-eyes reminder-move reminder-water reminder-caffeine reminder-sleep \
    tip-posture tip-strength tip-sleep tip-eyes tip-move tip-walk tip-offline tip-pain; do
    if [[ -f "$VOICE_SOURCE_DIR/$clip.m4a" ]]; then
      cp "$VOICE_SOURCE_DIR/$clip.m4a" "$APP_DIR/Contents/Resources/Voice/$clip.m4a"
    fi
  done
fi
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.aaaaqwq.nahida-companion</string>
  <key>CFBundleName</key><string>Nahida Companion</string>
  <key>CFBundleDisplayName</key><string>小纳西妲</string>
  <key>CFBundleExecutable</key><string>NahidaCompanion</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.6.0</string>
  <key>CFBundleVersion</key><string>11</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"
