#!/usr/bin/env bash
# orch_active_leaders — workers/ 의 모든 *.json 중 orch.json 만 제외 (mp-* 강제 X).

set -euo pipefail

ws="$SANDBOX/active-leaders"
mkdir -p "$ws/.orch/workers"
cd "$ws"

# orch.json + 다양한 leader 키
for name in orch MP-13 PROJ-456 142 issue42 gh-99; do
    cat > "$ws/.orch/workers/$name.json" <<EOF
{"worker_id":"$name","kind":"leader","scope":null,"window_id":"@1","pane_id":"%1","cwd":"$ws","started_at":"2026-05-11T00:00:00+00:00"}
EOF
done

# orch 자신은 leader 가 아니므로 kind=orch 로 덮어쓰기
cat > "$ws/.orch/workers/orch.json" <<EOF
{"worker_id":"orch","kind":"orch","scope":null,"window_id":"@1","pane_id":"%1","cwd":"$ws","started_at":"2026-05-11T00:00:00+00:00"}
EOF

ORCH_ROOT="$ws/.orch"
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/core/lib.sh"

mapfile -t got < <(orch_active_leaders | sort)
expected=("142" "MP-13" "PROJ-456" "gh-99" "issue42")

if [ "${#got[@]}" -ne "${#expected[@]}" ]; then
    echo "FAIL count: got=${#got[@]} want=${#expected[@]} (${got[*]})" >&2
    exit 1
fi
for i in "${!expected[@]}"; do
    if [ "${got[$i]}" != "${expected[$i]}" ]; then
        echo "FAIL index $i: got='${got[$i]}' want='${expected[$i]}'" >&2
        exit 1
    fi
done

# orch 자체는 제외되어야 함
for v in "${got[@]}"; do
    if [ "$v" = "orch" ]; then
        echo "FAIL orch should be excluded" >&2
        exit 1
    fi
done

echo "OK active-leaders-glob"
