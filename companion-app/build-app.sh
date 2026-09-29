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
if [[ -n "${NAHIDA_VOICE_DIR:-}" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources/Voice"
  for clip in greeting celebrate birthday; do
    cp "$NAHIDA_VOICE_DIR/$clip.m4a" "$APP_DIR/Contents/Resources/Voice/$clip.m4a"
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
  <key>CFBundleShortVersionString</key><string>0.5.3</string>
  <key>CFBundleVersion</key><string>10</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST
plutil -lint "$APP_DIR/Contents/Info.plist"
echo "$APP_DIR"
