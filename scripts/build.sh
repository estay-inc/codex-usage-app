#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
APP_NAME="Codex Usage.app"
APP_DIR="$BUILD_DIR/$APP_NAME"
SOURCE="$ROOT_DIR/Sources/CodexUsageMenuBar.swift"
PLIST="$ROOT_DIR/Resources/Info.plist"
ICON="$ROOT_DIR/Resources/AppIcon.icns"
MIN_MACOS="${MIN_MACOS:-13.0}"
ARCHS="${ARCHS:-native}"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR/objects"

compile_arch() {
  local arch="$1"
  local output="$BUILD_DIR/objects/CodexUsageMenuBar-$arch"
  swiftc \
    -O \
    -parse-as-library \
    -target "$arch-apple-macos$MIN_MACOS" \
    -framework AppKit \
    -framework ServiceManagement \
    "$SOURCE" \
    -o "$output"
}

if [[ "$ARCHS" == "universal" ]]; then
  compile_arch arm64
  compile_arch x86_64
  lipo -create \
    "$BUILD_DIR/objects/CodexUsageMenuBar-arm64" \
    "$BUILD_DIR/objects/CodexUsageMenuBar-x86_64" \
    -output "$APP_DIR/Contents/MacOS/CodexUsageMenuBar"
elif [[ "$ARCHS" == "native" ]]; then
  native_arch="$(uname -m)"
  compile_arch "$native_arch"
  cp "$BUILD_DIR/objects/CodexUsageMenuBar-$native_arch" \
    "$APP_DIR/Contents/MacOS/CodexUsageMenuBar"
else
  compile_arch "$ARCHS"
  cp "$BUILD_DIR/objects/CodexUsageMenuBar-$ARCHS" \
    "$APP_DIR/Contents/MacOS/CodexUsageMenuBar"
fi

cp "$PLIST" "$APP_DIR/Contents/Info.plist"
cp "$ICON" "$APP_DIR/Contents/Resources/AppIcon.icns"
for localization in "$ROOT_DIR"/Resources/*.lproj; do
  cp -R "$localization" "$APP_DIR/Contents/Resources/"
done
codesign --force --deep --sign - "$APP_DIR"
plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --verify --deep --strict "$APP_DIR"

if [[ "${PACKAGE:-0}" == "1" ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$BUILD_DIR/Codex-Usage-App.zip"
  echo "Created $BUILD_DIR/Codex-Usage-App.zip"
fi

if [[ "${DMG:-0}" == "1" ]]; then
  "$ROOT_DIR/scripts/package-dmg.sh"
fi

echo "Built $APP_DIR"
