#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT_DIR/scripts/build.sh"
bash -n "$ROOT_DIR/scripts/test.sh"
"$ROOT_DIR/scripts/build.sh"

if [[ "${CODEX_USAGE_LIVE_TEST:-0}" == "1" ]]; then
  "$ROOT_DIR/build/Codex Usage.app/Contents/MacOS/CodexUsageMenuBar" --self-test
else
  echo "Skipping live Codex test. Set CODEX_USAGE_LIVE_TEST=1 to enable it."
fi
