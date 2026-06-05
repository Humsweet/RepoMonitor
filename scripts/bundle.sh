#!/bin/bash
# Build and create a proper macOS .app bundle

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="RepoMonitor"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_BUNDLE="$PROJECT_DIR/build/${APP_NAME}.app"

echo "Building release..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>RepoMonitor</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.humsweet.RepoMonitor</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>RepoMonitor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Sign with a stable identity so Keychain "Always Allow" persists across
# rebuilds (ad-hoc signatures change every build and re-trigger prompts).
# Uses the first valid codesigning identity found in the keychain; override
# with REPOMONITOR_SIGN_IDENTITY if you have more than one.
SIGN_IDENTITY="${REPOMONITOR_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^ *1) [0-9A-F]* "\(.*\)"$/\1/p')}"
if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing with: $SIGN_IDENTITY"
    codesign --force --options runtime --identifier com.humsweet.RepoMonitor \
        --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
    echo "⚠ No codesigning identity found; falling back to ad-hoc (keychain prompts will recur)"
    codesign --force --sign - "$APP_BUNDLE"
fi

echo "✓ App bundle created at: $APP_BUNDLE"
echo ""
echo "To install: cp -r '$APP_BUNDLE' /Applications/"
echo "To run: open '$APP_BUNDLE'"
