#!/usr/bin/env bash
# notify-slack.sh — orch 이벤트를 Slack incoming webhook 으로 즉시 POST (PAD-8).
#
# 목적: 워커들이 동시다발로 끝났을 때 "지금 무엇을 확인해야 하는지" 사용자가
# 노트북 닫고 있어도 폰으로 알 수 있도록. 디바운스/큐 없음 — fire-and-forget.
#
# 실패 모드: webhook URL 미설정 / 네트워크 실패 / Slack 응답 비정상 → 모두 조용히
# exit 0. 호출자(mp-down 등) 의 본 흐름을 절대 막지 않는다.
#
# Webhook URL 조회 우선순위:
#   1. 환경변수 ORCH_SLACK_WEBHOOK
#   2. ${ORCH_ROOT}/notify.local.json 의 .slack_webhook_url 키 (jq 필요)
#   둘 다 없으면 조용히 종료.
#
# 명시적 비활성화: ORCH_NOTIFY_ENABLED=0
#
# 사용:
#   notify-slack.sh <category> [mp_id] [title] [link]
#
# category (PAD-8 합의):
#   mp_select        🤔  MP plan 컨펌 필요 (leader 가 막 떴고 plan 보낼 예정)
#   pr_open          🟡  PR 새로 생성됨, review 마커 부재 (리뷰 작업 남음)
#   pr_ready         🟢  PR review 마커 있음, 머지 가능
#   worker_question  ❓  워커 → orch 메시지 도착 (handoff 필요)
#   mp_done          ✅  mp-down 종료
#   error            🔴  errors.jsonl 새 entry

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh" 2>/dev/null || exit 0

# 비활성화 — opt-out.
[ "${ORCH_NOTIFY_ENABLED:-1}" = "0" ] && exit 0

cat="${1:-}"
mp_id="${2:-}"
title="${3:-}"
link="${4:-}"

[ -z "$cat" ] && exit 0   # 카테고리 없이 호출되면 noop (방어)

# webhook URL — env 또는 file.
webhook="${ORCH_SLACK_WEBHOOK:-}"
if [ -z "$webhook" ] && [ -f "${ORCH_ROOT}/notify.local.json" ] && command -v jq >/dev/null 2>&1; then
    webhook="$(jq -r '.slack_webhook_url // empty' "${ORCH_ROOT}/notify.local.json" 2>/dev/null || true)"
fi
[ -z "$webhook" ] && exit 0

case "$cat" in
    mp_select)       emoji="🤔"; label="MP plan 컨펌"     ;;
    pr_open)         emoji="🟡"; label="PR 생성 (리뷰 대기)" ;;
    pr_ready)        emoji="🟢"; label="PR 머지 가능"       ;;
    worker_question) emoji="❓"; label="워커 메시지"        ;;
    mp_done)         emoji="✅"; label="MP 완료"            ;;
    error)           emoji="🔴"; label="에러"               ;;
    *)
        # 알 수 없는 카테고리 — 호출자 버그. stderr 만 남기고 조용히 종료.
        echo "WARN: notify-slack.sh — unknown category '$cat'" >&2
        exit 0 ;;
esac

# 메시지 조립 — 한 줄 헤더 + 본문 + 링크. 짧고 스캔하기 좋게.
text="${emoji} *${label}*"
[ -n "$mp_id" ] && text+=" — \`${mp_id}\`"
[ -n "$title" ] && text+=$'\n'"${title}"
[ -n "$link" ]  && text+=$'\n'"<${link}>"

# JSON 페이로드 — jq 가 있으면 안전, 없으면 수동 escape.
if command -v jq >/dev/null 2>&1; then
    payload="$(jq -nc --arg t "$text" '{text: $t}' 2>/dev/null || true)"
fi
if [ -z "${payload:-}" ]; then
    # jq 없거나 실패 — 수동 escape.
    safe="$(printf '%s' "$text" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    safe="$(printf '%s' "$safe" | awk 'BEGIN{ORS="\\n"}{print}' | sed 's/\\n$//')"
    payload="{\"text\":\"${safe}\"}"
fi

# 5초 timeout, 실패는 조용히. 본 스크립트가 mp-down 같은 critical path 에서 호출되므로
# 절대 호출자 종료코드에 영향 주지 않도록 || true.
curl --silent --output /dev/null --max-time 5 \
    -X POST -H 'Content-Type: application/json' \
    --data "$payload" "$webhook" 2>/dev/null || true

exit 0
