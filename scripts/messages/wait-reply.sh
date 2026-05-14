#!/usr/bin/env bash
# $ORCH_BIN_DIR/messages/wait-reply.sh <q-id> [--timeout N]
# 워커가 leader 에 [question:<q-id>] 메시지를 보낸 후 호출한다.
# 자기 inbox 에서 본문에 [reply:<q-id>] 가 포함된 메시지가 도착할 때까지 폴링 (blocking).
#
#   exit 0  → 답 도착. stdout 에 frontmatter + 본문 출력 + archive 안내.
#   exit 2  → timeout 또는 사용 오류.
#
# 폴링은 wait-merge.sh 와 같은 패턴 (interval 30s, default timeout 1h).
# 답 도착 후 archive 는 호출자 책임 — 처리 결과를 leader 로 ack 답신한 다음에 archive 하는 것이 통상 패턴.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="$ORCH_SCRIPTS_ROOT"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/core/lib.sh
source "${ORCH_SCRIPTS_ROOT}/core/lib.sh"
orch_install_error_trap "$0"

usage() {
    cat >&2 <<EOF
사용법: wait-reply.sh <q-id> [--timeout SEC]
  q-id: 워커가 [question:<q-id>] 마커로 leader 에 송신할 때 사용한 식별자.
        예: q-1715432100-3f1a (사용자가 자유 형식). 공백 / 줄바꿈 금지.
  --timeout: 폴링 최대 시간 (초). 기본 3600 (1h). 환경변수 ORCH_WAIT_REPLY_TIMEOUT 으로 override.

워커 사용 패턴:
    qid="q-\$(date +%s)-\$RANDOM"
    bash -c "\$ORCH_BIN_DIR/messages/send.sh \$LEADER <<ORCH_MSG
    [question:\$qid]
    <질문 본문>
    ORCH_MSG"
    bash \$ORCH_BIN_DIR/messages/wait-reply.sh \$qid     # ← 차단. 답 받을 때까지 다음 마디 진행 X.
EOF
}

if [ "$#" -lt 1 ]; then
    usage
    exit 2
fi

qid="$1"
shift || true
timeout="${ORCH_WAIT_REPLY_TIMEOUT:-3600}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --timeout=*) timeout="${1#--timeout=}" ;;
        --timeout) shift; timeout="${1:-}" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: 알 수 없는 옵션 '$1'" >&2; usage; exit 2 ;;
    esac
    shift
done

case "$qid" in
    '' | *[[:space:]]*)
        echo "ERROR: 잘못된 q-id '$qid' (공백/빈 값 금지)" >&2
        exit 2
        ;;
esac

case "$timeout" in
    ''|*[!0-9]*)
        echo "ERROR: --timeout 은 정수 초 ('$timeout')" >&2
        exit 2
        ;;
esac

self="$(orch_detect_self 2>/dev/null || true)"
if [ -z "$self" ]; then
    echo "ERROR: worker_id 추론 실패 (ORCH_WORKER_ID 미설정?)" >&2
    exit 2
fi

inbox="$(orch_inbox_path "$self")" || {
    echo "ERROR: inbox 경로 결정 실패 (worker_id=$self)" >&2
    exit 2
}

interval="${ORCH_WAIT_REPLY_INTERVAL:-30}"
marker="[reply:${qid}]"
parse="${LIB_DIR}/inbox-parse.py"

echo "[wait-reply] qid=${qid} 폴링 시작 (간격 ${interval}s, timeout ${timeout}s, inbox=${inbox})" >&2

start_ts="$(date +%s)"
while :; do
    match_id=""
    if [ -s "$inbox" ]; then
        match_id="$(
            MARKER="$marker" INBOX="$inbox" PARSE="$parse" python3 <<'PY' 2>/dev/null || true
import os, runpy
mod = runpy.run_path(os.environ["PARSE"])
with open(os.environ["INBOX"], "r", encoding="utf-8", errors="replace") as f:
    msgs, _ = mod["parse"](f.read())
marker = os.environ["MARKER"]
for m in msgs:
    if marker in m["body"]:
        print(m["id"])
        break
PY
        )"
    fi

    if [ -n "$match_id" ]; then
        echo "[wait-reply] qid=${qid} 답 도착 (msg_id=${match_id})" >&2
        echo "=== REPLY worker_id=$self qid=$qid msg_id=$match_id ==="
        "$parse" body "$inbox" "$match_id" || true
        echo "=== END ==="
        echo "(처리 후 archive: bash \$ORCH_BIN_DIR/messages/inbox-archive.sh $match_id)"
        exit 0
    fi

    now="$(date +%s)"
    elapsed=$(( now - start_ts ))
    if [ "$elapsed" -ge "$timeout" ]; then
        echo "[wait-reply] timeout (${elapsed}s) — qid=${qid} 답 미도착" >&2
        exit 2
    fi

    sleep "$interval"
done
