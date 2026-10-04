#!/bin/bash
set -euo pipefail

# setup-cef.sh — Download and prepare official precompiled CEF binaries for macOS
# No Chromium compilation required.
# Uses official prebuilt CEF distributions from the Chromium Embedded Framework project.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_ROOT/Vendor/CEF"

ARCH="$(uname -m)"
if [ "$ARCH" = "arm64" ]; then
    CEF_ARCH="macosarm64"
else
    CEF_ARCH="macos64"
fi

# Pinned stable CEF version
CEF_VERSION="131.3.1+g0d94f27+chromium-131.0.6778.109"
CEF_BUNDLE="cef_binary_${CEF_VERSION}_${CEF_ARCH}_minimal"
CEF_TARBALL="${CEF_BUNDLE}.tar.bz2"
CEF_DOWNLOAD_URL="https://cef-builds.spotifycdn.com/${CEF_TARBALL}"

echo "=== NF Browser: Native Chromium (CEF) Setup ==="
echo "Architecture: $CEF_ARCH"
echo "CEF Version:  $CEF_VERSION"

mkdir -p "$VENDOR_DIR"

if [ -d "$VENDOR_DIR/Chromium Embedded Framework.framework" ]; then
    echo "✓ CEF Framework already installed in $VENDOR_DIR"
    exit 0
fi

echo "Downloading official prebuilt CEF binary..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if curl -fSL "$CEF_DOWNLOAD_URL" -o "$TMP_DIR/$CEF_TARBALL"; then
    echo "Extracting CEF package..."
    tar -xjf "$TMP_DIR/$CEF_TARBALL" -C "$TMP_DIR"
    
    if [ -d "$TMP_DIR/$CEF_BUNDLE/Release/Chromium Embedded Framework.framework" ]; then
        cp -R "$TMP_DIR/$CEF_BUNDLE/Release/Chromium Embedded Framework.framework" "$VENDOR_DIR/"
        echo "✓ Successfully installed Chromium Embedded Framework into $VENDOR_DIR"
    else
        echo "Note: Extracted files to $VENDOR_DIR"
        cp -R "$TMP_DIR/$CEF_BUNDLE"/* "$VENDOR_DIR/"
    fi
else
    echo "Could not download directly from Spotify CDN (network or version mismatch)."
    echo "You can manually place 'Chromium Embedded Framework.framework' into: $VENDOR_DIR"
fi

echo "=== CEF Setup complete ==="
