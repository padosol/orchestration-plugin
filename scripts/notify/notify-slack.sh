#!/usr/bin/env bash
# notify-slack.sh — orch 이벤트를 Slack incoming webhook 으로 즉시 POST.
#
# 목적: 워커들이 동시다발로 끝났을 때 "지금 무엇을 확인해야 하는지" 사용자가
# 노트북 닫고 있어도 폰으로 알 수 있도록. 디바운스/큐 없음 — fire-and-forget.
#
# 실패 모드: webhook URL 미설정 / 네트워크 실패 / Slack 응답 비정상 → 모두 조용히
# exit 0. 호출자(issue-down 등) 의 본 흐름을 절대 막지 않는다.
#
# 활성화 조건 (둘 다 만족해야 POST):
#   1. ${ORCH_ROOT}/settings.json 의 .notify.slack_enabled == true (master 토글 — 사용자가
#      cat 한 번으로 켜져있는지 확인 가능)
#   2. webhook URL 이 설정됨:
#      a. 환경변수 ORCH_SLACK_WEBHOOK
#      b. 또는 ${ORCH_ROOT}/notify.local.json 의 .slack_webhook_url 키 (jq 필요)
#   둘 중 하나라도 빠지면 조용히 종료 — 셋업 안 한 사용자 / 일반 개발 환경에서
#   소음 없도록.
#
# 임시 per-shell disable: ORCH_NOTIFY_ENABLED=0
#
# 사용:
#   notify-slack.sh <category> [mp_id] [title] [link]
#
# category:
#   mp_select        🤔  MP plan 컨펌 필요 (leader 가 막 떴고 plan 보낼 예정)
#   pr_open          🟡  PR 새로 생성됨, review 마커 부재 (리뷰 작업 남음)
#   pr_ready         🟢  PR review 마커 있음, 머지 가능
#   worker_question  ❓  워커 → orch 메시지 도착 (handoff 필요)
#   mp_done          ✅  issue-down 종료
#   error            🔴  errors.jsonl 새 entry

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="$ORCH_SCRIPTS_ROOT"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/core/lib.sh
source "${ORCH_SCRIPTS_ROOT}/core/lib.sh" 2>/dev/null || exit 0

cat="${1:-}"
mp_id="${2:-}"
title="${3:-}"
link="${4:-}"

# Slack 은 현재 유일한 notify provider. wrapper 이름은 기존 호출부 호환을 위해 유지.
# shellcheck source=/dev/null
source "${LIB_DIR}/providers/notify/slack.sh" 2>/dev/null || exit 0
orch_notify_provider_send "$cat" "$mp_id" "$title" "$link" || true

exit 0
