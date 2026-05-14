#!/usr/bin/env bash
# $ORCH_BIN_DIR/wait-merge.sh <pr-num>
# 워커가 자기 PR 의 머지를 폴링한다 (30s 간격, 24h timeout).
#   exit 0  → MERGED
#   exit 1  → CLOSED 미머지 (사용자가 닫음)
#   exit 2  → timeout 또는 사용 오류
# stderr 로 진행 상황 1줄씩 출력.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

if [ "$#" -lt 1 ]; then
    echo "사용법: wait-merge.sh <pr-num>" >&2
    exit 2
fi

pr="$1"
case "$pr" in
    ''|*[!0-9]*) echo "ERROR: pr-num은 숫자여야 함 ('$pr')" >&2; exit 2 ;;
esac

orch_require_git_host_cli || exit 2

interval="${ORCH_WAIT_MERGE_INTERVAL:-30}"
max_seconds="${ORCH_WAIT_MERGE_TIMEOUT:-86400}"   # 24h
start_ts="$(date +%s)"

echo "[wait-merge] PR #$pr 머지 대기 시작 (간격 ${interval}s, timeout ${max_seconds}s)" >&2

while :; do
    state="$(orch_pr_state "$pr")"
    case "$state" in
        merged)
            echo "[wait-merge] PR #$pr MERGED 감지" >&2
            exit 0 ;;
        closed)
            echo "pr_closed_without_merge: PR #$pr" >&2
            exit 1 ;;
        open|"")
            : ;;
        *)
            echo "[wait-merge] 알 수 없는 state='$state' — 계속 폴링" >&2 ;;
    esac

    now="$(date +%s)"
    elapsed=$(( now - start_ts ))
    if [ "$elapsed" -ge "$max_seconds" ]; then
        echo "[wait-merge] timeout (${elapsed}s) — 머지 안 됨" >&2
        exit 2
    fi

    sleep "$interval"
done
