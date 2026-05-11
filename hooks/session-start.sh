#!/usr/bin/env bash
# SessionStart hook for orch v2.
# ORCH_WORKER_ID(또는 후방호환 LOL_WORKER_ID) 환경변수가 설정된 워커 세션에서 동작.
# orch 도 /orch:up 후엔 등록되지만 환경변수 설정 안 돼있을 수 있음 — 그땐 hook 이 그냥 종료.

set -u

WORKER_ID="${ORCH_WORKER_ID:-${LOL_WORKER_ID:-}}"
[ -n "$WORKER_ID" ] || exit 0

# stdin payload에서 session_id 추출 (안내문 표시용 — 라우팅엔 안 씀)
session_id=""
if [ ! -t 0 ]; then
    payload="$(cat 2>/dev/null || true)"
    if [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
        session_id="$(printf '%s' "$payload" | jq -r '.session_id // ""' 2>/dev/null || echo "")"
    fi
fi

if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    # plugin hook 으로 실행되면 CLAUDE_PLUGIN_ROOT 가 자동 export 됨.
    # 환경변수 미설정 = 비정상 호출 (수동 실행 등) — 안내 없이 조용히 종료.
    exit 0
fi
LIB_PATH="${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
[ -f "$LIB_PATH" ] || exit 0
# shellcheck source=/dev/null
source "$LIB_PATH"

wid="$WORKER_ID"
kind="$(orch_wid_kind "$wid")"
[ "$kind" != "invalid" ] || exit 0

HAS_PENDING=0
INBOX_PATH="$(orch_inbox_path "$wid" 2>/dev/null || true)"
[ -n "$INBOX_PATH" ] && [ -s "$INBOX_PATH" ] && HAS_PENDING=1

case "$kind" in
    orch)
        ROLE_DESC="orchestrator (PM). 사용자와 직접 대화, leader에게 위임. 직접 워커 송신은 차단됨 — leader 통해서만. 결정이 옵션 2-4개로 깔끔하면 AskUserQuestion TUI 사용 (ToolSearch 로 스키마 먼저 로드)."
        CMDS="/orch:setup, /orch:up, /orch:issue-up, /orch:issue-down, /orch:send, /orch:check-inbox, /orch:status, /orch:prioritize, /orch:report, /orch:usage-stats"
        ;;
    leader)
        ROLE_DESC="${wid} 팀리더. 자기 MP 안에서 워커 spawn(/orch:leader-spawn) + 라우팅 + shutdown(/orch:issue-down) 책임. orch 보고 / 사용자 결정 받기. 산하 워커 간 통신은 leader 경유."
        CMDS="/orch:leader-spawn, /orch:send, /orch:check-inbox, /orch:issue-down"
        ;;
    worker)
        scope="${wid%%/*}"
        proj="${wid##*/}"
        ROLE_DESC="${scope} 산하 ${proj} 워커. 모든 외부 통신은 leader(${scope}) 경유. 코드 작업은 worktree 안에서, 커밋은 safe-commit."
        CMDS="/orch:send, /orch:check-inbox"
        ;;
esac

ADDITIONAL=""
if [ "$HAS_PENDING" -eq 1 ]; then
    ADDITIONAL=" Inbox 미처리 메시지 있음 → 먼저 /orch:check-inbox 실행할 것."
fi

session_suffix=""
[ -n "$session_id" ] && session_suffix=" [claude_session=${session_id:0:8}]"

escape_json() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

MSG="orch v2 worker_id=${wid}${session_suffix}. ${ROLE_DESC}${ADDITIONAL} 슬래시: ${CMDS}."

printf '{"systemMessage":"%s"}\n' "$(escape_json "$MSG")"
