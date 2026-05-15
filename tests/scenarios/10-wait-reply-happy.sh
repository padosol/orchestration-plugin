#!/usr/bin/env bash
# wait-reply.sh — inbox 에 이미 [reply:Q1] 메시지 있을 때 즉시 exit 0 + 본문 출력. (포인터 모델)

set -euo pipefail

ws="$SANDBOX/wait-reply-happy"
ib="$ws/.orch/runs/mp-99/inbox/test"
mkdir -p "$ib/payloads"

# 포인터 모델 메시지 수동 생성 (orch_append_message 산출 레이아웃 모사):
#   <ib>/<sortable>-<id>.json  +  <ib>/payloads/<id>.md
mkmsg() { # $1=seq $2=id $3=body
    printf '%s' "$3" > "$ib/payloads/$2.md"
    jq -nc --arg from mp-99 --arg to mp-99/test --arg ts 2026-05-11T12:00:00Z \
        --arg id "$2" --arg payload "$ib/payloads/$2.md" \
        '{from:$from,to:$to,ts:$ts,id:$id,payload:$payload}' \
        > "$ib/$(printf '%020d' "$1")-$2.json"
}

mkmsg 1 msg-001 '[reply:Q1]
GO. 진행하세요.'

out="$(
    ORCH_ROOT="$ws/.orch" \
    ORCH_WORKER_ID=mp-99/test \
    ORCH_WAIT_REPLY_INTERVAL=1 \
    ORCH_WAIT_REPLY_TIMEOUT=5 \
    bash "$PLUGIN_ROOT/scripts/messages/wait-reply.sh" Q1 2>&1
)"

echo "$out"

grep -qF "msg_id=msg-001" <<<"$out" || { echo "FAIL: msg_id not in output"; exit 1; }
grep -qF "GO. 진행하세요." <<<"$out" || { echo "FAIL: body not in output"; exit 1; }
grep -qF "qid=Q1" <<<"$out" || { echo "FAIL: qid label not in output"; exit 1; }

echo "OK wait-reply-happy"
