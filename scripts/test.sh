#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT_DIR/scripts/build.sh"
bash -n "$ROOT_DIR/scripts/package-dmg.sh"
bash -n "$ROOT_DIR/scripts/test.sh"
plutil -lint "$ROOT_DIR/Resources/en.lproj/Localizable.strings"
plutil -lint "$ROOT_DIR/Resources/ja.lproj/Localizable.strings"
plutil -lint "$ROOT_DIR/Resources/en.lproj/InfoPlist.strings"
plutil -lint "$ROOT_DIR/Resources/ja.lproj/InfoPlist.strings"
diff \
  <(sed -n 's/^"\([^"]*\)".*/\1/p' "$ROOT_DIR/Resources/en.lproj/Localizable.strings" | sort) \
  <(sed -n 's/^"\([^"]*\)".*/\1/p' "$ROOT_DIR/Resources/ja.lproj/Localizable.strings" | sort)
"$ROOT_DIR/scripts/build.sh"
test -f "$ROOT_DIR/build/Codex Usage.app/Contents/Resources/AppIcon.icns"
test -f "$ROOT_DIR/build/Codex Usage.app/Contents/Resources/en.lproj/Localizable.strings"
test -f "$ROOT_DIR/build/Codex Usage.app/Contents/Resources/ja.lproj/Localizable.strings"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$ROOT_DIR/build/Codex Usage.app/Contents/Info.plist")" = "AppIcon"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$ROOT_DIR/build/Codex Usage.app/Contents/Info.plist")" = "Codex Usage App"

english_output="$("$ROOT_DIR/build/Codex Usage.app/Contents/MacOS/CodexUsageMenuBar" -AppleLanguages '(en)' --localization-test)"
japanese_output="$("$ROOT_DIR/build/Codex Usage.app/Contents/MacOS/CodexUsageMenuBar" -AppleLanguages '(ja)' --localization-test)"
parser_output="$("$ROOT_DIR/build/Codex Usage.app/Contents/MacOS/CodexUsageMenuBar" --rate-limit-parser-test)"
history_output="$("$ROOT_DIR/build/Codex Usage.app/Contents/MacOS/CodexUsageMenuBar" --usage-history-test)"
grep -Fq 'move_title=Move to the Applications folder?' <<<"$english_output"
grep -Fq 'refresh=Refresh Now' <<<"$english_output"
grep -Fq 'quit=Quit' <<<"$english_output"
grep -Fq 'move_title=Applicationsフォルダへ移動しますか？' <<<"$japanese_output"
grep -Fq 'refresh=今すぐ更新' <<<"$japanese_output"
grep -Fq 'quit=終了' <<<"$japanese_output"
grep -Fq 'OK rate-limit-window-classification' <<<"$parser_output"
grep -Fq 'OK hourly-usage-history' <<<"$history_output"

install_test_dir="$(mktemp -d "$ROOT_DIR/build/install-test.XXXXXX")"
trap 'rm -rf "$install_test_dir"' EXIT
"$ROOT_DIR/build/Codex Usage.app/Contents/MacOS/CodexUsageMenuBar" \
  --self-install-test "$install_test_dir"
test -x "$install_test_dir/Codex Usage.app/Contents/MacOS/CodexUsageMenuBar"

if [[ "${CODEX_USAGE_LIVE_TEST:-0}" == "1" ]]; then
  "$ROOT_DIR/build/Codex Usage.app/Contents/MacOS/CodexUsageMenuBar" --self-test
else
  echo "Skipping live Codex test. Set CODEX_USAGE_LIVE_TEST=1 to enable it."
fi
