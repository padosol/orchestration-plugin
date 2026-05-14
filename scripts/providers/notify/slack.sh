#!/usr/bin/env bash
# Slack notify provider. Sourced by notify-slack.sh; do not execute directly.

orch_notify_provider_kind() {
    printf 'slack'
}

orch_notify_provider_send() {
    local cat="${1:-}" mp_id="${2:-}" title="${3:-}" link="${4:-}"
    local slack_enabled webhook emoji label text payload safe

    [ -z "$cat" ] && return 0

    # settings.json 의 master 토글. 미설정 / false / 파일 없음 → silent exit.
    [ -f "$ORCH_SETTINGS" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    slack_enabled="$(jq -r '.notify.slack_enabled // false' "$ORCH_SETTINGS" 2>/dev/null || echo false)"
    [ "$slack_enabled" = "true" ] || return 0

    # per-shell 임시 비활성화.
    [ "${ORCH_NOTIFY_ENABLED:-1}" = "0" ] && return 0

    # webhook URL — env 우선, 그 다음 notify.local.json. 없으면 silent exit.
    webhook="${ORCH_SLACK_WEBHOOK:-}"
    if [ -z "$webhook" ] && [ -f "${ORCH_ROOT}/notify.local.json" ]; then
        webhook="$(jq -r '.slack_webhook_url // empty' "${ORCH_ROOT}/notify.local.json" 2>/dev/null || true)"
    fi
    [ -z "$webhook" ] && return 0

    case "$cat" in
        mp_select)       emoji="🤔"; label="MP plan 컨펌"     ;;
        pr_open)         emoji="🟡"; label="PR 생성 (리뷰 대기)" ;;
        pr_ready)        emoji="🟢"; label="PR 머지 가능"       ;;
        worker_question) emoji="❓"; label="워커 메시지"        ;;
        mp_done)         emoji="✅"; label="MP 완료"            ;;
        error)           emoji="🔴"; label="에러"               ;;
        *)
            echo "WARN: notify provider slack — unknown category '$cat'" >&2
            return 0 ;;
    esac

    text="${emoji} *${label}*"
    [ -n "$mp_id" ] && text+=" — \`${mp_id}\`"
    [ -n "$title" ] && text+=$'\n'"${title}"
    [ -n "$link" ]  && text+=$'\n'"<${link}>"

    if command -v jq >/dev/null 2>&1; then
        payload="$(jq -nc --arg t "$text" '{text: $t}' 2>/dev/null || true)"
    fi
    if [ -z "${payload:-}" ]; then
        safe="$(printf '%s' "$text" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
        safe="$(printf '%s' "$safe" | awk 'BEGIN{ORS="\\n"}{print}' | sed 's/\\n$//')"
        payload="{\"text\":\"${safe}\"}"
    fi

    curl --silent --output /dev/null --max-time 5 \
        -X POST -H 'Content-Type: application/json' \
        --data "$payload" "$webhook" 2>/dev/null || true
}
