#!/usr/bin/env bash
# setup.sh --update — 기존 settings.json 이 없으면 새 .orch root 를 만들지 않고 실패해야 한다.

set -euo pipefail

ws="$SANDBOX/setup-update-requires-existing"
mkdir -p "$ws/repo-a"

out="$SANDBOX/setup-update-requires-existing.out"
if ORCH_ROOT="$ws/.orch" bash "$PLUGIN_ROOT/scripts/config/setup.sh" --update >"$out" 2>&1; then
    echo "FAIL: settings.json 없이 --update 가 성공함" >&2
    exit 1
fi

if [ -d "$ws/.orch" ] || [ -e "$ws/.orch/settings.json" ]; then
    echo "FAIL: settings.json 없는 --update 가 새 .orch 를 생성함" >&2
    exit 1
fi

grep -q 'settings.json' "$out" || {
    echo "FAIL: 실패 메시지에 settings.json 안내 누락" >&2
    cat "$out" >&2
    exit 1
}

echo "OK setup-update-requires-existing"
