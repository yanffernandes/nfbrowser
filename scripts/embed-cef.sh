#!/bin/bash
set -euo pipefail

# embed-cef.sh — Xcode post-build phase of the NFBrowser target.
# Copies the CEF framework (versioned layout, as Xcode 26+ requires) and the
# five Chromium helper apps into NFBrowser.app/Contents/Frameworks.

CEF_DIST="$SRCROOT/Vendor/CEF/dist"
FRAMEWORK_NAME="Chromium Embedded Framework.framework"
FRAMEWORK_SRC="$CEF_DIST/Release/$FRAMEWORK_NAME"
FRAMEWORKS_DIR="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
FRAMEWORK_DST="$FRAMEWORKS_DIR/$FRAMEWORK_NAME"
VERSION_STAMP="$DERIVED_FILE_DIR/embedded-cef-version"
CEF_VERSION="$(cat "$SRCROOT/Vendor/CEF/.installed-version" 2>/dev/null || true)"
KEEP_LOCALES=(en en_GB es es_419 pt_BR pt_PT)
HELPER_SUFFIXES=("" " (Alerts)" " (GPU)" " (Plugin)" " (Renderer)")

if [[ ! -d "$FRAMEWORK_SRC" || -z "$CEF_VERSION" ]]; then
    echo "error: CEF is not set up. Run ./scripts/setup-cef.sh"
    exit 1
fi

mkdir -p "$FRAMEWORKS_DIR" "$DERIVED_FILE_DIR"

if [[ ! -d "$FRAMEWORK_DST" || "$(cat "$VERSION_STAMP" 2>/dev/null || true)" != "$CEF_VERSION" ]]; then
    echo "Embedding $FRAMEWORK_NAME ($CEF_VERSION)"
    rm -rf "$FRAMEWORK_DST"
    mkdir -p "$FRAMEWORK_DST/Versions"
    # -c clones on APFS, so the ~320 MB copy costs no time or space.
    cp -Rc "$FRAMEWORK_SRC" "$FRAMEWORK_DST/Versions/A"

    for lproj in "$FRAMEWORK_DST/Versions/A/Resources/"*.lproj; do
        locale="$(basename "$lproj" .lproj)"
        if [[ ! " ${KEEP_LOCALES[*]} " =~ " $locale " ]]; then
            rm -rf "$lproj"
        fi
    done

    ln -sfn A "$FRAMEWORK_DST/Versions/Current"
    ln -sfn "Versions/Current/Chromium Embedded Framework" "$FRAMEWORK_DST/Chromium Embedded Framework"
    ln -sfn "Versions/Current/Libraries" "$FRAMEWORK_DST/Libraries"
    ln -sfn "Versions/Current/Resources" "$FRAMEWORK_DST/Resources"
    echo "$CEF_VERSION" > "$VERSION_STAMP"
fi

for suffix in "${HELPER_SUFFIXES[@]}"; do
    helper="NFBrowser Helper$suffix.app"
    if [[ ! -d "$BUILT_PRODUCTS_DIR/$helper" ]]; then
        echo "error: $helper was not built"
        exit 1
    fi
    rsync -a --delete "$BUILT_PRODUCTS_DIR/$helper/" "$FRAMEWORKS_DIR/$helper/"
done

# When Xcode signs the app, nested code has to be signed first (inside-out).
if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
    for library in "$FRAMEWORK_DST/Versions/A/Libraries/"*.dylib; do
        codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$library"
    done
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$FRAMEWORK_DST"
    for suffix in "${HELPER_SUFFIXES[@]}"; do
        codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$FRAMEWORKS_DIR/NFBrowser Helper$suffix.app"
    done
fi
