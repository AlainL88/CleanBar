#!/bin/bash
set -e

echo "🔨 Compilazione CleanBar (Release)..."
xcodebuild -project CleanBar.xcodeproj -scheme CleanBar -configuration Release -destination "platform=macOS" -quiet build

BUILD_APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/CleanBar-*/Build/Products/Release -name "CleanBar.app" -type d | head -n 1)

if [ -z "$BUILD_APP_PATH" ]; then
  echo "❌ Errore: Impossibile trovare CleanBar.app compilata."
  exit 1
fi

pkill -x CleanBar 2>/dev/null || true
rm -rf /Applications/CleanBar.app 2>/dev/null || sudo rm -rf /Applications/CleanBar.app 2>/dev/null || true
cp -R "$BUILD_APP_PATH" /Applications/

# Sign with Developer Certificate for persistent macOS TCC Accessibility authorization
DEV_ID="Apple Development: Alain Lima (Q6659PDF69)"
if security find-identity -v -p codesigning | grep -q "Apple Development: Alain Lima"; then
  codesign --force --deep --sign "Apple Development: Alain Lima (Q6659PDF69)" /Applications/CleanBar.app 2>/dev/null || codesign --force --deep --sign - /Applications/CleanBar.app 2>/dev/null || true
else
  codesign --force --deep --sign - /Applications/CleanBar.app 2>/dev/null || true
fi

echo "✅ CleanBar installata con successo in /Applications/CleanBar.app"
open /Applications/CleanBar.app
