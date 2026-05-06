#!/usr/bin/env bash
# /orch:check-inbox [<msg-id>]
# - 인자 없음: 메시지 요약 표 (id, from, ts, 첫 50자) — 사용자/LLM 이 단건 골라 처리.
# - <msg-id> 지정: 해당 메시지 본문만 출력 — LLM 이 한 건씩 처리.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

self="$(orch_detect_self 2>/dev/null || true)"
if [ -z "$self" ]; then
    echo "ERROR: worker_id 추론 실패. ORCH_WORKER_ID(또는 LOL_WORKER_ID) 또는 등록된 pane 필요." >&2
    exit 2
fi

inbox="$(orch_inbox_path "$self")"
if [ ! -s "$inbox" ]; then
    echo "INBOX_EMPTY worker_id=$self"
    exit 0
fi

mkdir -p "$(dirname "$inbox")"

if [ "$#" -ge 1 ] && [ -n "$1" ]; then
    # 단건 모드
    msg_id="$1"
    {
        flock -s 9
        echo "=== INBOX worker_id=$self id=$msg_id ==="
        python3 "${LIB_DIR}/inbox-parse.py" body "$inbox" "$msg_id"
        echo "=== END ==="
        echo "(처리 후 단건 archive: \$ORCH_BIN_DIR/inbox-archive.sh $msg_id)"
    } 9>"${inbox}.lock"
else
    # 요약 모드
    {
        flock -s 9
        summary="$(python3 "${LIB_DIR}/inbox-parse.py" summary "$inbox" 2>/dev/null || true)"
        if [ -z "$summary" ]; then
            # frontmatter 가 없거나 파싱 실패 — raw 출력 fallback
            echo "=== INBOX worker_id=$self path=$inbox (파싱 실패, raw 출력) ==="
            cat "$inbox"
            echo "=== END ==="
        else
            count="$(printf '%s\n' "$summary" | grep -c .)"
            # summary 는 reverse 정렬돼 있음 (최신 위) — 첫 줄이 가장 최신 ID.
            first_id="$(printf '%s\n' "$summary" | head -1 | cut -f1)"
            echo "=== INBOX worker_id=$self count=$count (최신 위) ==="
            printf 'id\tfrom\tts\tfirst-50\n'
            printf '%s\n' "$summary"
            echo "=== END ==="
            echo ""
            echo "▶ 다음 호출 (필수): /orch:check-inbox $first_id   ← message_id 인자 강제"
            echo "  단건 archive: \$ORCH_BIN_DIR/inbox-archive.sh <id>"
            echo "  ⚠ 이 요약 출력만 보고 종료/답신/archive 절대 금지."
            echo "  ⚠ 사용자에게 보고할 때는 반드시 [id=xxx] 형식으로 message_id 명시."
        fi
    } 9>"${inbox}.lock"
fi
