#!/bin/sh
set -eu

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"
CACHE_DIR="${TMPDIR:-/private/tmp}/rant-swift-build-cache"
mkdir -p "$CACHE_DIR/clang" "$CACHE_DIR/modules" "$CACHE_DIR/spm"
CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_DIR/modules" \
swift build --disable-sandbox --cache-path "$CACHE_DIR/spm" --scratch-path "$CACHE_DIR/build" -c release

OUTPUT="$APP_DIR/dist/Rant.app"
mkdir -p "$OUTPUT/Contents/MacOS" "$OUTPUT/Contents/Resources"
cp "$CACHE_DIR/build/release/Rant" "$OUTPUT/Contents/MacOS/Rant"
cp Resources/Info.plist "$OUTPUT/Contents/Info.plist"
printf 'APPL????' > "$OUTPUT/Contents/PkgInfo"
/usr/bin/codesign --force --deep --sign - "$OUTPUT"
printf 'Built %s\n' "$OUTPUT"
