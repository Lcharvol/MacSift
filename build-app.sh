#!/bin/bash
set -e

CONFIG="${1:-debug}"
APP_NAME="MacSift"
BUNDLE="$APP_NAME.app"
BUNDLE_ID="com.macsift.app"

echo "Building $APP_NAME ($CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH=".build/$(swift build -c "$CONFIG" --show-bin-path)"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

echo "Creating $BUNDLE..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "Ad-hoc signing..."
codesign --force --deep --sign - "$BUNDLE" 2>&1 | grep -v "replacing existing signature" || true

echo "✅ Built $BUNDLE"
echo "Run with: open $BUNDLE"
echo ""
echo "⚠️  First-time setup: grant Full Disk Access"
echo "   System Settings → Privacy & Security → Full Disk Access"
echo "   Add: $(pwd)/$BUNDLE"
