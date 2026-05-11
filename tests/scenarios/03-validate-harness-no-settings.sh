#!/usr/bin/env bash
# validate-harness — orch workspace 가 아닌 cwd 에서 호출 → silent no-op exit 0.

set -euo pipefail

ws="$SANDBOX/validate-harness-no-settings"
mkdir -p "$ws"  # .orch 없음

out="$(cd "$ws" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/hooks/validate-harness.sh")"

if [ -n "$out" ]; then
    echo "FAIL: 비-orch 환경에서 출력 발생:"
    echo "$out"
    exit 1
fi

echo "OK validate-harness-no-settings (silent exit 0)"
