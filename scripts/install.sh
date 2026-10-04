#!/bin/bash
set -euo pipefail

# install.sh — Build and install the latest NFBrowser into /Applications
# Usage: ./scripts/install.sh [--launch]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="NFBrowser.app"
DEST_PATH="/Applications/$APP_NAME"
ENTITLEMENTS="$ROOT_DIR/NFBrowser/Info/NFBrowser-debug.entitlements"

echo "==> Building latest NFBrowser..."
cd "$ROOT_DIR"

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen
fi

set -o pipefail && xcodebuild build \
  -scheme NFBrowser \
  -destination "platform=macOS" \
  -configuration Debug \
  -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO | (command -v xcbeautify >/dev/null 2>&1 && xcbeautify || cat)

echo "==> Locating built bundle..."
BUILT_APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 6 -name "$APP_NAME" -type d 2>/dev/null | grep -E "Debug/$APP_NAME" | head -n 1 || true)

if [[ -z "$BUILT_APP" || ! -d "$BUILT_APP" ]]; then
    echo "Error: Built app not found!"
    exit 1
fi

echo "==> Installing to $DEST_PATH..."
# Quit running instances if any (both new NFBrowser and old NF Browser)
pkill -f "$APP_NAME/Contents/MacOS/NFBrowser" 2>/dev/null || true
pkill -f "NF Browser.app/Contents/MacOS/NF Browser" 2>/dev/null || true
sleep 1

# Remove existing installations
rm -rf "$DEST_PATH"
rm -rf "/Applications/NF Browser.app"
rm -rf "$HOME/Applications/$APP_NAME"
rm -rf "$HOME/Applications/NF Browser.app"

# Copy new bundle
ditto "$BUILT_APP" "$DEST_PATH"

echo "==> Signing ad-hoc with debug entitlements and registering..."
xattr -dr com.apple.quarantine "$DEST_PATH" 2>/dev/null || true

if [[ -f "$ENTITLEMENTS" ]]; then
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$DEST_PATH"
else
    codesign --force --deep --sign - "$DEST_PATH"
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f -r "$DEST_PATH"
fi
mdimport "$DEST_PATH" 2>/dev/null || true

echo "==> Successfully installed $DEST_PATH"

if [[ "${1:-}" == "--launch" ]]; then
    echo "==> Launching $DEST_PATH..."
    open "$DEST_PATH"
fi
