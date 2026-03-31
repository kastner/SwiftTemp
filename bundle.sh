#!/bin/bash
set -e

APP_NAME="SwiftTemp"
BUNDLE_DIR="$APP_NAME.app"
CONTENTS="$BUNDLE_DIR/Contents"
MACOS="$CONTENTS/MacOS"

cd "$(dirname "$0")"

# Build
swift build 2>&1

# Create .app bundle
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS"

# Copy binary
cp ".build/debug/$APP_NAME" "$MACOS/$APP_NAME"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>SwiftTemp</string>
	<key>CFBundleIdentifier</key>
	<string>com.swifttemp.app</string>
	<key>CFBundleName</key>
	<string>SwiftTemp</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>SwiftTemp needs your location to show local weather.</string>
	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
	<string>SwiftTemp needs your location to show local weather.</string>
	<key>NSLocationUsageDescription</key>
	<string>SwiftTemp needs your location to show local weather.</string>
</dict>
</plist>
EOF

echo "Built $BUNDLE_DIR successfully!"
echo "Run with: open $BUNDLE_DIR"
