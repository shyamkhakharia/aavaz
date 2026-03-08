#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

APP_NAME="Aavaz"
BUNDLE_ID="com.aavaz.app"
VERSION="0.1.0"
BUILD_DIR="$PROJECT_ROOT/.build/release"
APP_DIR="$PROJECT_ROOT/build/${APP_NAME}.app"

echo "Building release binary..."
cd "$PROJECT_ROOT"
swift build -c release 2>&1

echo "Generating app icon..."
swift "$SCRIPT_DIR/generate-icon.swift" "$PROJECT_ROOT/build"

echo "Assembling .app bundle..."

# Clean previous bundle
rm -rf "$APP_DIR"

# Create bundle structure
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/Aavaz" "$APP_DIR/Contents/MacOS/${APP_NAME}"

# Copy icon
if [ -f "$PROJECT_ROOT/build/AppIcon.icns" ]; then
    cp "$PROJECT_ROOT/build/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Aavaz needs microphone access to record your voice for transcription.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc code sign
codesign --force --sign - "$APP_DIR"

echo ""
echo "App bundle created at: $APP_DIR"
echo "To run: open $APP_DIR"
