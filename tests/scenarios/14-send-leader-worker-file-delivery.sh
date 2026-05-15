#!/usr/bin/env bash
# send.sh — leader ↔ worker 메시지는 tmux 알림 없이 파일 inbox 에만 queue. (포인터 모델)

set -euo pipefail

ws="$SANDBOX/send-leader-worker-file-delivery"
mkdir -p "$ws/.orch"

out="$(
    ORCH_ROOT="$ws/.orch" \
    ORCH_WORKER_ID=mp-99 \
    bash "$PLUGIN_ROOT/scripts/messages/send.sh" mp-99/api '작업 시작하세요' 2>&1
)"

echo "$out"

grep -qF "file-queued delivery only" <<<"$out" || { echo "FAIL: 파일 queue 안내 누락"; exit 1; }
grep -qF "mp-99 → mp-99/api" <<<"$out" || { echo "FAIL: 송신 결과 누락"; exit 1; }
if grep -qi 'tmux' <<<"$out"; then
    echo "FAIL: leader→worker 기본 송신에서 tmux 알림을 시도하면 안 됨"
    exit 1
fi

# 포인터 모델: 레거시 단일 .md 파일이 아니라 디렉터리 + pointer + payload.
ib="$ws/.orch/runs/mp-99/inbox/api"
[ ! -f "$ws/.orch/runs/mp-99/inbox/api.md" ] || { echo "FAIL: 레거시 api.md 가 생성됨"; exit 1; }
[ -d "$ib" ] || { echo "FAIL: worker inbox 디렉터리 미생성: $ib"; exit 1; }

ptr="$(find "$ib" -maxdepth 1 -name '*.json' -type f | head -1)"
[ -n "$ptr" ] || { echo "FAIL: pointer JSON 미생성"; exit 1; }
[ "$(jq -r '.from' "$ptr")" = "mp-99" ] || { echo "FAIL: pointer.from != mp-99"; exit 1; }
[ "$(jq -r '.to' "$ptr")" = "mp-99/api" ] || { echo "FAIL: pointer.to != mp-99/api"; exit 1; }

payload="$(jq -r '.payload' "$ptr")"
[ -f "$payload" ] || { echo "FAIL: payload 파일 미생성: $payload"; exit 1; }
grep -qF "작업 시작하세요" "$payload" || { echo "FAIL: payload 본문 누락"; exit 1; }

echo "OK send-leader-worker-file-delivery"
