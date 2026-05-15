#!/usr/bin/env bash
# wait-reply.sh — 다른 q-id 답 / 마커 없는 메시지가 와도 무시하고 폴링 지속. (포인터 모델)
# 짧은 timeout 안에 매칭 안 되면 exit 2. 매칭 메시지 추가하면 exit 0.

set -euo pipefail

ws="$SANDBOX/wait-reply-ignores-other"
ib="$ws/.orch/runs/mp-99/inbox/test"
mkdir -p "$ib/payloads"

mkmsg() { # $1=seq $2=id $3=body
    printf '%s' "$3" > "$ib/payloads/$2.md"
    jq -nc --arg from mp-99 --arg to mp-99/test --arg ts 2026-05-11T12:00:00Z \
        --arg id "$2" --arg payload "$ib/payloads/$2.md" \
        '{from:$from,to:$to,ts:$ts,id:$id,payload:$payload}' \
        > "$ib/$(printf '%020d' "$1")-$2.json"
}

mkmsg 1 msg-other-1 '[reply:OTHER]
다른 질문 답입니다.'
mkmsg 2 msg-fyi '일반 FYI 메시지 (마커 없음).'

# Q1 매칭 메시지 없음 → timeout
set +e
ORCH_ROOT="$ws/.orch" ORCH_WORKER_ID=mp-99/test \
    ORCH_WAIT_REPLY_INTERVAL=1 ORCH_WAIT_REPLY_TIMEOUT=2 \
    bash "$PLUGIN_ROOT/scripts/messages/wait-reply.sh" Q1 > /tmp/wr-out 2>&1
code=$?
set -e
[ "$code" -eq 2 ] || { echo "FAIL: 다른 마커는 무시해야 하는데 exit $code"; cat /tmp/wr-out; exit 1; }

# 이제 Q1 매칭 메시지 추가 → wait-reply 다시 호출 시 즉시 발견
mkmsg 3 msg-target '[reply:Q1]
이번엔 Q1 답.'

out=$(
    ORCH_ROOT="$ws/.orch" ORCH_WORKER_ID=mp-99/test \
        ORCH_WAIT_REPLY_INTERVAL=1 ORCH_WAIT_REPLY_TIMEOUT=3 \
        bash "$PLUGIN_ROOT/scripts/messages/wait-reply.sh" Q1 2>&1
)

echo "$out"

grep -qF "msg_id=msg-target" <<<"$out" || { echo "FAIL: Q1 매칭이 msg-target 을 가리켜야 함"; exit 1; }
grep -qF "이번엔 Q1 답" <<<"$out" || { echo "FAIL: 본문 누락"; exit 1; }

echo "OK wait-reply-ignores-other"
