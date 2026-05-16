#!/usr/bin/env bash
# SessionStart hook (orch v2).
# spawn 된 leader/worker 의 부트스트랩을 inbox 의 spawn-context(첫 메시지)를
# 셸에서 직접 드레인해 plain stdout 으로 주입한다. SessionStart 는 plain stdout 을
# 자동으로 모델 컨텍스트에 추가하므로 JSON 래퍼도 start skill indirection 도 불필요.
# orch(PM) 는 spawn-context 가 없으므로 역할 안내만.

set -u

WORKER_ID="${ORCH_WORKER_ID:-${LOL_WORKER_ID:-}}"
[ -n "$WORKER_ID" ] || exit 0

# stdin payload 에서 session_id 추출 (표시용 — 라우팅엔 안 씀)
session_id=""
if [ ! -t 0 ]; then
    payload="$(cat 2>/dev/null || true)"
    if [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
        session_id="$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null || echo "")"
    fi
fi

[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || exit 0
LIB_PATH="${CLAUDE_PLUGIN_ROOT}/scripts/core/lib.sh"
[ -f "$LIB_PATH" ] || exit 0
# shellcheck source=/dev/null
source "$LIB_PATH"

wid="$WORKER_ID"
kind="$(orch_wid_kind "$wid")"
[ "$kind" != "invalid" ] || exit 0

session_suffix=""
[ -n "$session_id" ] && session_suffix=" [claude_session=${session_id:0:8}]"

if [ "$kind" = "orch" ]; then
    printf 'orch v2 worker_id=%s%s. orchestrator(PM). 사용자와 직접 대화, leader 에게 위임. 직접 워커 송신 차단 — leader 경유. 결정이 옵션 2-4개로 깔끔하면 AskUserQuestion TUI (ToolSearch 로 스키마 먼저 로드). 슬래시: /orch:setup, /orch:up, /orch:issue-up, /orch:issue-down, /orch:send, /orch:check-inbox, /orch:poll-inbox, /orch:status, /orch:prioritize, /orch:report, /orch:usage-stats\n' "$wid" "$session_suffix"
    exit 0
fi

# leader/worker — inbox 의 첫(최古) 메시지 = spawn-context (spawn 스크립트가 claude
# 기동 전에 적재). 셸에서 드레인해 그대로 컨텍스트로 주입.
parse="${CLAUDE_PLUGIN_ROOT}/scripts/inbox-parse.py"
dir="$(orch_inbox_dir "$wid" 2>/dev/null || true)"
first_id=""
[ -n "$dir" ] && [ -d "$dir" ] && first_id="$(python3 "$parse" ids "$dir" 2>/dev/null | head -1 || true)"

if [ -z "$first_id" ]; then
    # spawn-context 미도착 또는 이미 드레인됨(세션 재개/clear/compact 재fire).
    # 재부트스트랩 금지 — 런타임 inbox 폴링으로 진행.
    printf 'orch v2 worker_id=%s%s. spawn-context 없음 — 런타임 inbox 폴링으로 진행 (/orch:poll-inbox 또는 /orch:check-inbox). 슬래시: /orch:send, /orch:check-inbox, /orch:poll-inbox\n' "$wid" "$session_suffix"
    exit 0
fi

# payload 경로는 id 로 결정적: <dir>/payloads/<id>.md
body=""
pf="$dir/payloads/${first_id}.md"
[ -f "$pf" ] && body="$(cat "$pf")"

if [ -z "$body" ]; then
    printf 'orch v2 worker_id=%s%s. spawn-context payload 읽기 실패(id=%s) — /orch:check-inbox 로 직접 수령하라. 슬래시: /orch:send, /orch:check-inbox, /orch:poll-inbox\n' "$wid" "$session_suffix" "$first_id"
    exit 0
fi

printf 'orch v2 worker_id=%s%s. 아래는 너의 spawn-context (작업 지시) 다. 다른 어떤 행동보다 먼저 이 본문을 그대로 따른다:\n\n%s\n' "$wid" "$session_suffix" "$body"

# 전달 완료 — 단건 archive. 런타임 inbox 폴링이 spawn-context 를 재처리하지
# 않도록 inbox 에서 빼고 archive 에 보존. stdout 오염 방지로 출력 버린다.
arch="${CLAUDE_PLUGIN_ROOT}/scripts/messages/inbox-archive.sh"
[ -f "$arch" ] && bash "$arch" "$first_id" >/dev/null 2>&1 || true

exit 0
