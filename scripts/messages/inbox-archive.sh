#!/usr/bin/env bash
# inbox-archive.sh <msg-id>
# inbox-archive.sh --all     (위험 — 한 번에 모두 archive. 평소 사용 금지)
#
# 단건 archive 가 기본. 메시지 한 건씩 처리 후 archive 하는 운영 패턴을 강제하기 위해
# argument 없이 호출하면 거부한다 — 일괄 archive 는 메시지 누락 위험.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="$ORCH_SCRIPTS_ROOT"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/core/lib.sh
source "${ORCH_SCRIPTS_ROOT}/core/lib.sh"
orch_install_error_trap "$0"

self="$(orch_detect_self 2>/dev/null || true)"
if [ -z "$self" ]; then
    echo "ERROR: worker_id 추론 실패" >&2
    exit 2
fi

inbox="$(orch_inbox_path "$self")"
archive="$(orch_archive_path "$self")"

if [ ! -s "$inbox" ]; then
    echo "INBOX_EMPTY worker_id=$self"
    exit 0
fi

mkdir -p "$(dirname "$archive")"

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
    echo "ERROR: <msg-id> 인자 필요. 메시지 한 건씩 처리하고 그 ID 만 archive 하세요." >&2
    echo "  - 단건: \$ORCH_BIN_DIR/messages/inbox-archive.sh <msg-id>" >&2
    echo "  - 일괄(긴급용 — 평소 사용 금지): \$ORCH_BIN_DIR/messages/inbox-archive.sh --all" >&2
    echo "" >&2
    echo "현재 inbox 메시지 ID 목록:" >&2
    python3 "${LIB_DIR}/inbox-parse.py" ids "$inbox" | sed 's/^/  /' >&2
    exit 2
fi

case "$1" in
    --all)
        # 전체 모드 — 운영 사고 복구용 escape hatch
        {
            flock -x 9
            cat "$inbox" >> "$archive"
            : > "$inbox"
        } 9>"${inbox}.lock"
        echo "ARCHIVED worker_id=$self to=$archive (whole inbox — --all 사용)"
        ;;
    *)
        # 단건 모드
        msg_id="$1"
        {
            flock -x 9
            # extract 가 실패하면 (id 미존재) 여기서 멈춤 — set -e
            block="$(python3 "${LIB_DIR}/inbox-parse.py" extract "$inbox" "$msg_id")"
            new_inbox="$(python3 "${LIB_DIR}/inbox-parse.py" remove "$inbox" "$msg_id")"
            printf '%s' "$block" >> "$archive"
            printf '%s' "$new_inbox" > "$inbox"
        } 9>"${inbox}.lock"
        echo "ARCHIVED worker_id=$self id=$msg_id to=$archive"
        ;;
esac
