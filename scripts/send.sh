#!/usr/bin/env bash
# /orch:send <target> <message> — 2-tier hub-and-spoke 메시지 전송.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

if [ "$#" -lt 1 ]; then
    cat >&2 <<EOF
사용법:
  send.sh <target> <message...>           (argv — 단순/한줄용)
  send.sh <target> --file <path>          (파일 본문 — 따옴표/괄호/줄바꿈 모두 안전. 권장)
  send.sh <target> < body.txt             (stdin redirect — 단순한 단일 명령에서만)
  send.sh <target> <<'EOF' ... EOF        (heredoc — 직접 셸에서만. bash -c 안에서 쓰지 말 것)
target 예시: orch | mp-13 | mp-13/server

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
    echo "  허용 형식: orch | mp-NN | mp-NN/<project>" >&2
    exit 2
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
orch_notify "$target" "$msg_id"

echo "OK [${msg_id}] ${from} → ${target}"
