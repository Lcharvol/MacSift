#!/bin/bash
set -e

CONFIG="${1:-debug}"
APP_NAME="MacSift"
BUNDLE="$APP_NAME.app"
BUNDLE_ID="com.macsift.app"

# -------------------------------------------------------------------------
# Prerequisites check
# -------------------------------------------------------------------------
# Swift 6.0+ is required (project uses swift-tools-version: 6.0 and macOS 26
# Liquid Glass APIs). macOS 26+ is required to run the resulting binary.

if ! command -v swift >/dev/null 2>&1; then
    echo "❌ swift not found in PATH."
    echo "   Install Xcode 26 command-line tools: xcode-select --install"
    exit 1
fi

swift_version=$(swift --version 2>/dev/null | head -1 | grep -oE 'version [0-9]+\.[0-9]+' | awk '{print $2}')
swift_major=${swift_version%.*}
if [ -z "$swift_version" ] || [ "$swift_major" -lt 6 ] 2>/dev/null; then
    echo "❌ Swift $swift_version detected. MacSift requires Swift 6.0 or later."
    echo "   Install Xcode 26 or newer."
    exit 1
fi

macos_version=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)
if [ -n "$macos_version" ] && [ "$macos_version" -lt 26 ] 2>/dev/null; then
    echo "⚠️  macOS $macos_version detected. MacSift targets macOS 26 (Tahoe)."
    echo "   The build may succeed but the resulting binary won't launch here."
    echo "   Continue anyway? [y/N]"
    read -r answer
    [ "$answer" = "y" ] || [ "$answer" = "Y" ] || exit 1
fi

echo "Building $APP_NAME ($CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH=".build/$(swift build -c "$CONFIG" --show-bin-path)"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

echo "Creating $BUNDLE..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"

# Embed app icon if present
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Derive the version from git. Release builds should tag BEFORE invoking
# build-app.sh so the tag is in place. If no tag is reachable (dev build),
# we fall back to "0.0.0-dev" which the in-app update checker treats as
# "always behind latest release".
VERSION="${VERSION:-}"
if [ -z "$VERSION" ]; then
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
fi
if [ -z "$VERSION" ]; then
    VERSION="0.0.0-dev"
fi
echo "Using version: $VERSION"

cat > "$BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
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
