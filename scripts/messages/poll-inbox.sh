#!/usr/bin/env bash
# /orch:poll-inbox [--timeout SEC] [--interval SEC]
# 자기 inbox 에 처리할 메시지가 생길 때까지 파일 기반으로 폴링한 뒤 최신 메시지 본문 출력.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="$ORCH_SCRIPTS_ROOT"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/core/lib.sh
source "${ORCH_SCRIPTS_ROOT}/core/lib.sh"
orch_install_error_trap "$0"

usage() {
    cat >&2 <<EOF
사용법: poll-inbox.sh [--timeout SEC] [--interval SEC]
  --timeout: 최대 대기 시간. 기본 3600초. 환경변수 ORCH_POLL_INBOX_TIMEOUT 으로 override.
  --interval: 폴링 간격. 기본 5초. 환경변수 ORCH_POLL_INBOX_INTERVAL 로 override.

새 leader/worker 세션의 첫 지시 수신처럼 "아직 메시지가 없을 수 있는" 구간에서 사용한다.
메시지가 이미 있으면 즉시 최신 메시지 본문을 출력한다.
EOF
}

timeout="${ORCH_POLL_INBOX_TIMEOUT:-3600}"
interval="${ORCH_POLL_INBOX_INTERVAL:-5}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --timeout=*) timeout="${1#--timeout=}" ;;
        --timeout) shift; timeout="${1:-}" ;;
        --interval=*) interval="${1#--interval=}" ;;
        --interval) shift; interval="${1:-}" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: 알 수 없는 옵션 '$1'" >&2; usage; exit 2 ;;
    esac
    shift
done

case "$timeout" in
    ''|*[!0-9]*)
        echo "ERROR: --timeout 은 정수 초 ('$timeout')" >&2
        exit 2
        ;;
esac
case "$interval" in
    ''|*[!0-9]*)
        echo "ERROR: --interval 은 정수 초 ('$interval')" >&2
        exit 2
        ;;
esac

self="$(orch_detect_self 2>/dev/null || true)"
if [ -z "$self" ]; then
    echo "ERROR: worker_id 추론 실패. ORCH_WORKER_ID(또는 LOL_WORKER_ID) 또는 등록된 pane 필요." >&2
    exit 2
fi

inbox="$(orch_inbox_path "$self")" || {
    echo "ERROR: inbox 경로 결정 실패 (worker_id=$self)" >&2
    exit 2
}
mkdir -p "$(dirname "$inbox")"
touch "$inbox"

parse="${LIB_DIR}/inbox-parse.py"
echo "[poll-inbox] worker_id=${self} 폴링 시작 (간격 ${interval}s, timeout ${timeout}s, inbox=${inbox})" >&2

start_ts="$(date +%s)"
while :; do
    first_id=""
    if [ -s "$inbox" ]; then
        first_id="$(
            flock -s 9
            python3 "$parse" summary "$inbox" 2>/dev/null | head -1 | cut -f1
        )" 9>"${inbox}.lock"
    fi

    if [ -n "$first_id" ]; then
        echo "[poll-inbox] 메시지 도착 (msg_id=${first_id})" >&2
        {
            flock -s 9
            echo "=== INBOX worker_id=$self id=$first_id ==="
            python3 "$parse" body "$inbox" "$first_id"
            echo "=== END ==="
            echo "(처리 후 단건 archive: \$ORCH_BIN_DIR/messages/inbox-archive.sh $first_id)"
        } 9>"${inbox}.lock"
        exit 0
    fi

    now="$(date +%s)"
    elapsed=$(( now - start_ts ))
    if [ "$elapsed" -ge "$timeout" ]; then
        echo "[poll-inbox] timeout (${elapsed}s) — 메시지 미도착" >&2
        exit 2
    fi

    sleep "$interval"
done
