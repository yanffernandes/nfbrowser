#!/bin/bash
set -euo pipefail

# setup-cef.sh — Download the pinned CEF (Chromium Embedded Framework) binary
# distribution and build libcef_dll_wrapper for the host architecture.
#
# Usage: ./scripts/setup-cef.sh [--force]
#
# Output (gitignored):
#   Vendor/CEF/dist/                         extracted minimal distribution
#   Vendor/CEF/dist/build/libcef_dll_wrapper/libcef_dll_wrapper.a
#
# Requires: curl, shasum, cmake, ninja (brew install cmake ninja).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_ROOT/Vendor/CEF"
DIST_DIR="$VENDOR_DIR/dist"
BUILD_DIR="$DIST_DIR/build"
STAMP_FILE="$VENDOR_DIR/.installed-version"

CEF_VERSION="154.0.34+g14c5a08+chromium-154.0.8037.98"

case "$(uname -m)" in
    arm64)
        CEF_PLATFORM="macosarm64"
        PROJECT_ARCH="arm64"
        CEF_SHA1="b7081f6609e5edccf07be96b5d7977329fbe1bdf"
        ;;
    x86_64)
        CEF_PLATFORM="macosx64"
        PROJECT_ARCH="x86_64"
        CEF_SHA1="51d90349e24360b8e0daecc2d026ad150c620db5"
        ;;
    *)
        echo "Unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

CEF_BUNDLE="cef_binary_${CEF_VERSION}_${CEF_PLATFORM}_minimal"
CEF_TARBALL="${CEF_BUNDLE}.tar.bz2"
CEF_DOWNLOAD_URL="https://cef-builds.spotifycdn.com/${CEF_TARBALL//+/%2B}"
WRAPPER_LIB="$BUILD_DIR/libcef_dll_wrapper/libcef_dll_wrapper.a"
EXPECTED_STAMP="$CEF_VERSION $CEF_PLATFORM"

for tool in curl shasum cmake ninja; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing required tool: $tool (brew install cmake ninja)" >&2
        exit 1
    }
done

if [[ "${1:-}" != "--force" && -f "$STAMP_FILE" && -f "$WRAPPER_LIB" ]] \
    && [[ "$(cat "$STAMP_FILE")" == "$EXPECTED_STAMP" ]]; then
    echo "CEF $CEF_VERSION ($CEF_PLATFORM) already set up in $DIST_DIR"
    exit 0
fi

echo "==> CEF $CEF_VERSION ($CEF_PLATFORM)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> Downloading $CEF_TARBALL"
curl -fSL --retry 3 "$CEF_DOWNLOAD_URL" -o "$TMP_DIR/$CEF_TARBALL"

echo "==> Verifying SHA-1"
ACTUAL_SHA1="$(shasum -a 1 "$TMP_DIR/$CEF_TARBALL" | cut -d' ' -f1)"
if [[ "$ACTUAL_SHA1" != "$CEF_SHA1" ]]; then
    echo "SHA-1 mismatch: expected $CEF_SHA1, got $ACTUAL_SHA1" >&2
    exit 1
fi

echo "==> Extracting"
mkdir -p "$TMP_DIR/extract"
tar -xjf "$TMP_DIR/$CEF_TARBALL" -C "$TMP_DIR/extract"
[[ -d "$TMP_DIR/extract/$CEF_BUNDLE/Release/Chromium Embedded Framework.framework" ]] || {
    echo "Unexpected archive layout: framework not found" >&2
    exit 1
}
rm -rf "$DIST_DIR"
mkdir -p "$VENDOR_DIR"
mv "$TMP_DIR/extract/$CEF_BUNDLE" "$DIST_DIR"

echo "==> Building libcef_dll_wrapper"
cmake -G Ninja -S "$DIST_DIR" -B "$BUILD_DIR" \
    -DPROJECT_ARCH="$PROJECT_ARCH" \
    -DCMAKE_BUILD_TYPE=Release
ninja -C "$BUILD_DIR" libcef_dll_wrapper
[[ -f "$WRAPPER_LIB" ]] || {
    echo "libcef_dll_wrapper.a was not produced" >&2
    exit 1
}

echo "$EXPECTED_STAMP" > "$STAMP_FILE"
echo "==> CEF ready: $DIST_DIR"
