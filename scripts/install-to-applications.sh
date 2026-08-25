#!/bin/bash
set -e

echo "🔨 Building CleanBar in Release configuration..."
xcodebuild -project CleanBar.xcodeproj -scheme CleanBar -configuration Release build

BUILD_APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/CleanBar-*/Build/Products/Release -name "CleanBar.app" -type d | head -n 1)

if [ -z "$BUILD_APP_PATH" ]; then
  echo "❌ Error: Could not find built CleanBar.app"
  exit 1
fi

echo "📦 Found built app at: $BUILD_APP_PATH"

# If previous app in /Applications is running, close it
pkill -x CleanBar 2>/dev/null || true

# Copy to /Applications
echo "🚀 Installing to /Applications/CleanBar.app..."
rm -rf /Applications/CleanBar.app 2>/dev/null || sudo rm -rf /Applications/CleanBar.app 2>/dev/null || true
cp -R "$BUILD_APP_PATH" /Applications/

echo "✅ CleanBar successfully installed in /Applications/CleanBar.app!"
echo "✨ Launching CleanBar..."
open /Applications/CleanBar.app
