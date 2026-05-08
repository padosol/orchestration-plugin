#!/usr/bin/env bash
# /orch:ask — orch 가 사용자에게 결정 요청을 비동기 큐에 등록.
# 호출자: orch (PM pane) 만. 등록 후 stdout 에 q-id 출력.
# 사용:
#   ask.sh "<context>" "<question>" [--option key=label]... [--allow-freeform]
# 예:
#   ask.sh "MP-12 follow-up 결정" "권장 follow-up 6건 전부 등록할까요?" \
#       --option all="전부 등록" --option high="High 만" --option skip="폐기"

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/dev/null
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

usage() {
    cat >&2 <<EOF
사용법: /orch:ask "<context>" "<question>" [옵션]
  <context>     — 어떤 작업의 어떤 결정인지 (예: "MP-12 follow-up 결정")
  <question>    — 사용자에게 보여줄 본문

  --option key=label  — 선택지 (반복 허용). 2~4개 권장.
  --allow-freeform    — 자유 텍스트 답변 허용 (기본: false, --text 로만 답)

호출자: orch pane 전용.
EOF
    exit 2
}

self="$(orch_detect_self 2>/dev/null || true)"
if [ "$self" != "orch" ]; then
    echo "ERROR: /orch:ask 는 orch pane 전용 (현재: ${self:-unknown})" >&2
    exit 2
fi

if [ "$#" -lt 2 ]; then
    usage
fi

context="$1"; shift
question="$1"; shift

allow_freeform=false
options_json='[]'
while [ "$#" -gt 0 ]; do
    case "$1" in
        --option)
            shift
            spec="${1:-}"
            [ -n "$spec" ] || { echo "ERROR: --option 뒤 key=label 필요" >&2; exit 2; }
            key="${spec%%=*}"
            label="${spec#*=}"
            if [ -z "$key" ] || [ "$key" = "$spec" ]; then
                echo "ERROR: --option 인자는 key=label 형식 ('$spec')" >&2; exit 2
            fi
            options_json="$(jq --arg k "$key" --arg l "$label" '. + [{key: $k, label: $l}]' <<<"$options_json")"
            ;;
        --allow-freeform) allow_freeform=true ;;
        -h|--help) usage ;;
        *) echo "ERROR: 알 수 없는 옵션: $1" >&2; exit 2 ;;
    esac
    shift
done

mkdir -p "$ORCH_QUESTIONS"

id="$(orch_new_question_id)"
ts="$(date -Iseconds)"
path="$(orch_question_path "$id")"

jq -n \
    --arg id "$id" \
    --arg ctx "$context" \
    --arg q "$question" \
    --argjson opts "$options_json" \
    --argjson freeform "$allow_freeform" \
    --arg ts "$ts" \
    '{
        id: $id,
        from_context: $ctx,
        question: $q,
        options: $opts,
        allow_freeform: $freeform,
        ts: $ts,
        status: "open",
        answer: null
    }' >"$path"

echo "$id"
echo "  path: $path" >&2
echo "  context: $context" >&2
echo "  options: $(jq -r '[.[] | .key] | join(",")' <<<"$options_json")" >&2
echo "  allow_freeform: $allow_freeform" >&2
echo "  사용자에게 안내: '/orch:questions $id' 로 본문 확인, '/orch:answer $id <key>' 로 답변" >&2
