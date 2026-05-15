#!/usr/bin/env bash
# /orch:peek <worker-id>
# 워커 pane 의 마지막 30줄 + 활동 시각 + inbox 카운트 출력. 멈춘 워커 진단용.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="$ORCH_SCRIPTS_ROOT"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/core/lib.sh
source "${ORCH_SCRIPTS_ROOT}/core/lib.sh"
orch_install_error_trap "$0"

if [ "$#" -lt 1 ]; then
    echo "사용법: /orch:peek <worker-id>" >&2
    exit 2
fi

target="$1"
target_kind="$(orch_wid_kind "$target")"
if [ "$target_kind" = "invalid" ]; then
    echo "ERROR: worker_id '$target' 형식 오류 (orch | <issue_id> | <issue_id>/<project>)" >&2
    exit 2
fi

self="$(orch_detect_self 2>/dev/null || true)"
self_kind="$(orch_wid_kind "${self:-}")"

case "$self_kind" in
    orch)
        ;;  # orch 는 모두 peek 가능
    leader)
        target_scope="$(orch_wid_scope "$target")"
        if [ "$target" != "$self" ] && [ "$target_scope" != "$self" ]; then
            echo "ERROR: leader '$self' 는 자기 자신/산하 워커만 peek 가능 (대상: $target)" >&2
            exit 2
        fi
        ;;
    *)
        echo "ERROR: peek 는 orch 또는 leader 에서만 호출 가능 (현재: ${self:-unknown})" >&2
        exit 2
        ;;
esac

if ! orch_worker_exists "$target"; then
    echo "ERROR: '$target' 등록 없음" >&2
    exit 2
fi

pane_id="$(orch_worker_field "$target" pane_id 2>/dev/null || true)"
window_id="$(orch_worker_field "$target" window_id 2>/dev/null || true)"
started_at="$(orch_worker_field "$target" started_at 2>/dev/null || true)"
inbox_n="$(orch_inbox_count "$target" 2>/dev/null || echo 0)"
inbox_path="$(orch_inbox_dir "$target" 2>/dev/null || true)"

if ! orch_pane_alive "$pane_id"; then
    cat <<EOF
=== peek $target ===
status:        DEAD (pane $pane_id 가 tmux 에 없음 — registry 잔재)
window:        $window_id
started:       $started_at
inbox:         ${inbox_n}건 ($inbox_path)
=== END ===
EOF
    exit 0
fi

last_used="$(tmux display-message -p -t "$pane_id" '#{t:pane_last_used}' 2>/dev/null || true)"
[ -z "$last_used" ] && last_used="(미상)"

cat <<EOF
=== peek $target ===
status:        ALIVE
pane:          $pane_id
window:        $window_id
started:       $started_at
last_used:     $last_used
inbox:         ${inbox_n}건 ($inbox_path)
--- last 30 lines of pane ---
EOF
tmux capture-pane -pt "$pane_id" -S -30 2>/dev/null || echo "(capture 실패)"
echo "=== END ==="
