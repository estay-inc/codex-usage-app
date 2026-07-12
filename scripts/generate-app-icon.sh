#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-icon.XXXXXX")"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
MASTER_PNG="$WORK_DIR/AppIcon-1024.png"
OUTPUT="$ROOT_DIR/Resources/AppIcon.icns"

trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$ICONSET_DIR"

swift "$ROOT_DIR/scripts/generate-app-icon.swift" "$MASTER_PNG"

make_icon() {
  local size="$1"
  local filename="$2"
  sips -z "$size" "$size" "$MASTER_PNG" --out "$ICONSET_DIR/$filename" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT"
echo "Created $OUTPUT"
