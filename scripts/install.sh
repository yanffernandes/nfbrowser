#!/bin/bash
set -euo pipefail

# install.sh — Build and install the latest NF Browser into /Applications
# Usage: ./scripts/install.sh [--launch]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="NF Browser.app"
DEST_PATH="/Applications/$APP_NAME"
DERIVED_DATA_APP="$HOME/Library/Developer/Xcode/DerivedData/Ora-hevuafdhmmqttmfplwogwkyfjlif/Build/Products/Debug/$APP_NAME"

echo "==> Building latest NF Browser..."
cd "$ROOT_DIR"

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen
fi

set -o pipefail && xcodebuild build \
  -scheme ora \
  -destination "platform=macOS" \
  -configuration Debug \
  -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO | (command -v xcbeautify >/dev/null 2>&1 && xcbeautify || cat)

echo "==> Locating built bundle..."
BUILT_APP=""
if [[ -d "$DERIVED_DATA_APP" ]]; then
    BUILT_APP="$DERIVED_DATA_APP"
else
    BUILT_APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 5 -name "$APP_NAME" -type d 2>/dev/null | grep -E "Debug/$APP_NAME" | head -n 1 || true)
fi

if [[ -z "$BUILT_APP" || ! -d "$BUILT_APP" ]]; then
    echo "Error: Built app not found!"
    exit 1
fi

echo "==> Installing to $DEST_PATH..."
# Quit running instance if any
pkill -f "$APP_NAME/Contents/MacOS/NF Browser" 2>/dev/null || true
sleep 1

# Remove existing installation
rm -rf "$DEST_PATH"
# Also clean any stale user Applications copy
rm -rf "$HOME/Applications/$APP_NAME"

# Copy new bundle
ditto "$BUILT_APP" "$DEST_PATH"

echo "==> Signing ad-hoc and registering..."
xattr -dr com.apple.quarantine "$DEST_PATH" 2>/dev/null || true
codesign --force --deep --sign - "$DEST_PATH"

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
