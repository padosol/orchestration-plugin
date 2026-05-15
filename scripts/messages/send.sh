#!/usr/bin/env bash
# /orch:send <target> <message> — 2-tier hub-and-spoke 메시지 전송.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="$ORCH_SCRIPTS_ROOT"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/core/lib.sh
source "${ORCH_SCRIPTS_ROOT}/core/lib.sh"
orch_install_error_trap "$0"

if [ "$#" -lt 1 ]; then
    cat >&2 <<EOF
사용법:
  send.sh <target> <message...>           (argv — 단순/한줄용)
  send.sh <target> --file <path>          (파일 본문 — 따옴표/괄호/줄바꿈 모두 안전. 권장)
  send.sh <target> < body.txt             (stdin redirect — 단순한 단일 명령에서만)
  send.sh <target> <<'EOF' ... EOF        (heredoc — 직접 셸에서만. bash -c 안에서 쓰지 말 것)
target 예시: orch | MP-13 | MP-13/server | PROJ-456/ui | 142/api

⚠ \`bash -c "send.sh ... <<EOF ..."\` 같이 따옴표 안에 heredoc 넣으면 외부 따옴표/괄호와
충돌해 syntax error 가 난다. 본문이 한 줄이 아니거나 따옴표·괄호를 포함하면 반드시
\`--file\` 모드를 쓰자: 임시 파일에 본문 쓰고 그 경로 전달.
EOF
    exit 2
fi

target="$1"
shift

# --file 모드: 임시파일/일반파일에서 본문 읽기. heredoc 우회용 — bash -c 와 함께 써도 안전.
if [ "$#" -ge 2 ] && [ "$1" = "--file" ]; then
    body_file="$2"
    if [ ! -f "$body_file" ]; then
        echo "ERROR: --file 경로 없음: $body_file" >&2
        exit 2
    fi
    body="$(cat "$body_file")"
    shift 2
    # 추가 인자가 남아 있으면 사용자 실수 — 명확히 거부
    if [ "$#" -gt 0 ]; then
        echo "ERROR: --file 모드에서 추가 인자 사용 불가 (남은 인자: $*)" >&2
        exit 2
    fi
elif [ "$#" -gt 0 ]; then
    body="$*"
elif [ ! -t 0 ]; then
    body="$(cat)"
else
    echo "ERROR: 메시지 본문 없음 (argv, --file, 또는 stdin 으로 전달)" >&2
    exit 2
fi

if [ -z "$body" ]; then
    echo "ERROR: 빈 메시지 송신 불가" >&2
    exit 2
fi

if ! orch_is_valid_worker_id "$target"; then
    echo "ERROR: 잘못된 target worker_id: '$target'" >&2
    echo "  허용 형식: orch | <issue_id> | <issue_id>/<project>  (issue_id = [A-Za-z0-9_-]+)" >&2
    exit 2
fi

# 'MP-75' / 'mp-75' 처럼 case 혼용으로 등록 inbox 와 어긋나는 사고 방지 (PAD-60).
# registry 에 case-insensitive 매칭되는 worker_id 가 있으면 등록 case 로 정규화.
resolved_target="$(orch_resolve_worker_id_case "$target")"
if [ "$resolved_target" != "$target" ]; then
    echo "INFO: target case 정규화 '${target}' → '${resolved_target}' (registry 등록 case)" >&2
    target="$resolved_target"
fi

from="$(orch_detect_self 2>/dev/null || true)"
if [ -z "$from" ]; then
    echo "ERROR: 보낸이 worker_id 추론 실패." >&2
    echo "  - ORCH_WORKER_ID(또는 LOL_WORKER_ID) 환경변수가 설정 안 됐고" >&2
    echo "  - 현재 pane이 .orch/workers 레지스트리에 등록되지 않았습니다." >&2
    echo "  orch pane이라면 먼저 /orch:up 으로 등록하세요." >&2
    exit 2
fi

if ! orch_route_check "$from" "$target"; then
    exit 2
fi

msg_id="$(orch_append_message "$from" "$target" "$body")"

# 모든 worker (orch 포함) 는 파일 inbox 를 canonical delivery 로 사용한다 — 폴링 일원화.
# tmux send-keys 활성화는 spawn 시점에만 (leader-spawn/review-spawn 직접 호출) 일어나며,
# 그 이후 모든 메시지는 inbox append + 수신자가 자체 poll-inbox/check-inbox 로 수령.
# 디버깅 용 escape hatch: ORCH_TMUX_NOTIFY=1 일 때만 강제 send-keys push.
if [ "${ORCH_TMUX_NOTIFY:-0}" = "1" ]; then
    orch_notify "$target" "$msg_id"
else
    echo "INFO: file-queued delivery only — ${target} should poll inbox (msg_id=${msg_id})" >&2
fi

# Slack 알림 — worker → orch 메시지는 사용자가 봐야 할 신호.
# 본문에 "PR # ... ready for review" 패턴 있으면 pr_open 이 더 구체적이라 그쪽 우선.
if [ "$from" != "orch" ]; then
    scope="$(orch_wid_scope "$from" 2>/dev/null || true)"
    if printf '%s' "$body" | grep -qiE 'PR #[0-9]+ ready for review'; then
        pr_url="$(printf '%s' "$body" | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | head -n1 || true)"
        pr_num="$(printf '%s' "$body" | grep -oE 'PR #[0-9]+' | head -n1 || true)"
        "${LIB_DIR}/notify/notify-slack.sh" pr_open "$scope" "${pr_num} ready for review (from ${from})" "$pr_url" || true
    elif [ "$target" = "orch" ]; then
        # 짧은 본문 미리보기 (한 줄, 80자) — Slack 메시지가 너무 길어지지 않게.
        preview="$(printf '%s' "$body" | tr '\n' ' ' | cut -c1-80)"
        "${LIB_DIR}/notify/notify-slack.sh" worker_question "$scope" "${from}: ${preview}" || true
    fi
fi

echo "OK [${msg_id}] ${from} → ${target} (${#body} chars)"
