#!/usr/bin/env bash
# 포인터 모델 — append → pointer/payload 레이아웃 → count → FIFO poll → 단건 consume → archive → find-marker.

set -euo pipefail

ws="$SANDBOX/pointer-model-roundtrip"
mkdir -p "$ws/.orch/workers" "$ws/.orch/runs/mp-99/workers"
printf '{"worker_id":"orch","role":"orch","pane_id":"%%1","cwd":"%s"}\n' "$ws" > "$ws/.orch/workers/orch.json"
printf '{"worker_id":"mp-99","role":"leader","pane_id":"%%2","cwd":"%s"}\n' "$ws" > "$ws/.orch/workers/mp-99.json"
printf '{"worker_id":"mp-99/api","role":"worker","pane_id":"%%3","cwd":"%s"}\n' "$ws" > "$ws/.orch/runs/mp-99/workers/api.json"

send() {
    ORCH_ROOT="$ws/.orch" ORCH_WORKER_ID=mp-99 \
        bash "$PLUGIN_ROOT/scripts/messages/send.sh" mp-99/api "$1" >/dev/null 2>&1
}

send 'MSG-A first'
sleep 0.05
send 'MSG-B second'
sleep 0.05
send 'MSG-C third'

ib="$ws/.orch/runs/mp-99/inbox/api"

# 1. 레거시 단일 .md inbox 가 생기면 안 됨
[ ! -f "$ws/.orch/runs/mp-99/inbox/api.md" ] || { echo "FAIL: 레거시 api.md 파일이 생성됨"; exit 1; }

# 2. pointer 3 + payload 3
nptr="$(find "$ib" -maxdepth 1 -name '*.json' -type f | wc -l)"
npay="$(find "$ib/payloads" -maxdepth 1 -name '*.md' -type f | wc -l)"
[ "$nptr" -eq 3 ] || { echo "FAIL: pointer 수 $nptr (기대 3)"; exit 1; }
[ "$npay" -eq 3 ] || { echo "FAIL: payload 수 $npay (기대 3)"; exit 1; }

# 3. pointer JSON 필수 필드
ptr0="$(find "$ib" -maxdepth 1 -name '*.json' -type f | sort | head -1)"
for k in from to ts id payload; do
    jq -e --arg k "$k" 'has($k)' "$ptr0" >/dev/null || { echo "FAIL: pointer 에 '$k' 필드 없음"; exit 1; }
done
[ "$(jq -r '.from' "$ptr0")" = "mp-99" ] || { echo "FAIL: from != mp-99"; exit 1; }
[ "$(jq -r '.to' "$ptr0")" = "mp-99/api" ] || { echo "FAIL: to != mp-99/api"; exit 1; }
payload_path="$(jq -r '.payload' "$ptr0")"
[ -f "$payload_path" ] || { echo "FAIL: payload 경로가 실제 파일 아님: $payload_path"; exit 1; }

# 4. count
cnt="$(ORCH_ROOT="$ws/.orch" bash -c "source '$PLUGIN_ROOT/scripts/core/lib.sh'; orch_inbox_count mp-99/api")"
[ "$cnt" -eq 3 ] || { echo "FAIL: orch_inbox_count $cnt (기대 3)"; exit 1; }

# 5. poll-inbox → FIFO 가장 오래된 (MSG-A) 먼저
pout="$(ORCH_ROOT="$ws/.orch" ORCH_WORKER_ID=mp-99/api \
    bash "$PLUGIN_ROOT/scripts/messages/poll-inbox.sh" --timeout 2 --interval 1 2>&1)"
grep -qF 'MSG-A first' <<<"$pout" || { echo "FAIL: poll-inbox 가 FIFO 가장 오래된 메시지 출력 안 함"; exit 1; }
grep -qF 'MSG-B' <<<"$pout" && { echo "FAIL: poll-inbox 가 한 번에 한 건 초과 출력"; exit 1; }

# 6. 단건 archive — 가장 오래된 1건만 consume, 나머지 FIFO 보존
first_id="$(ORCH_ROOT="$ws/.orch" ORCH_WORKER_ID=mp-99/api \
    bash "$PLUGIN_ROOT/scripts/messages/inbox.sh" 2>&1 | grep -oE '^[0-9]+-[a-z0-9]+' | head -1)"
ORCH_ROOT="$ws/.orch" ORCH_WORKER_ID=mp-99/api \
    bash "$PLUGIN_ROOT/scripts/messages/inbox-archive.sh" "$first_id" >/dev/null 2>&1
[ "$(find "$ib" -maxdepth 1 -name '*.json' -type f | wc -l)" -eq 2 ] \
    || { echo "FAIL: archive 후 pointer 2 아님"; exit 1; }
[ "$(find "$ib/payloads" -maxdepth 1 -name '*.md' -type f | wc -l)" -eq 2 ] \
    || { echo "FAIL: archive 후 payload 2 아님 (orphan payload?)"; exit 1; }
nxt="$(ORCH_ROOT="$ws/.orch" ORCH_WORKER_ID=mp-99/api \
    bash "$PLUGIN_ROOT/scripts/messages/inbox.sh" 2>&1)"
grep -qF 'MSG-B second' <<<"$nxt" || { echo "FAIL: archive 후 다음 FIFO = MSG-B 가 아님"; exit 1; }
grep -qF 'MSG-A first' <<<"$nxt" && { echo "FAIL: 소비된 MSG-A 가 아직 inbox 에 있음"; exit 1; }

# 7. archive 파일에 소비된 블록 보존
arch="$(find "$ws/.orch/runs/mp-99/archive" -name 'api-*.md' -type f | head -1)"
[ -n "$arch" ] || { echo "FAIL: archive 파일 미생성"; exit 1; }
grep -qF 'MSG-A first' "$arch" || { echo "FAIL: archive 에 소비 본문 없음"; exit 1; }
grep -qF "id: $first_id" "$arch" || { echo "FAIL: archive 블록에 id frontmatter 없음"; exit 1; }

# 8. find-marker (wait-reply 경로)
send '[reply:Q1]
GO 진행하세요.'
rout="$(ORCH_ROOT="$ws/.orch" ORCH_WORKER_ID=mp-99/api \
    ORCH_WAIT_REPLY_INTERVAL=1 ORCH_WAIT_REPLY_TIMEOUT=3 \
    bash "$PLUGIN_ROOT/scripts/messages/wait-reply.sh" Q1 2>&1)"
grep -qF 'qid=Q1' <<<"$rout" || { echo "FAIL: wait-reply qid 라벨 누락"; exit 1; }
grep -qF 'GO 진행하세요.' <<<"$rout" || { echo "FAIL: wait-reply 본문 누락"; exit 1; }

echo "OK pointer-model-roundtrip"
