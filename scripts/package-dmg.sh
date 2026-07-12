#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
APP_DIR="$BUILD_DIR/Codex Usage.app"
DMG_PATH="$BUILD_DIR/Codex Usage App.dmg"

if [[ ! -d "$APP_DIR" ]]; then
  ARCHS=universal "$ROOT_DIR/scripts/build.sh"
fi

staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-dmg.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

ditto "$APP_DIR" "$staging_dir/Codex Usage.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
  -volname "Codex Usage App" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH"
echo "Created $DMG_PATH"
