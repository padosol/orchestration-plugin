#!/usr/bin/env bash
# /orch:answer <q-id> <key>
# /orch:answer <q-id> --text "<자유 답변>"
# 사용자가 큐에 등록된 질문에 답한다. status=answered 로 표시 + orch inbox 에 메시지.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/dev/null
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

usage() {
    cat >&2 <<EOF
사용법:
  /orch:answer <q-id> <key>            — 옵션 키 선택
  /orch:answer <q-id> --text "<답변>"  — 자유 텍스트 답변 (allow_freeform 인 경우)

  --text 와 <key> 동시 사용 불가.
EOF
    exit 2
}

if [ "$#" -lt 2 ]; then
    usage
fi

id="$1"; shift
mode=""
key=""
text=""

case "$1" in
    --text)
        shift
        [ "$#" -ge 1 ] || usage
        mode="text"
        text="$1"
        ;;
    --text=*)
        mode="text"
        text="${1#--text=}"
        ;;
    -h|--help) usage ;;
    *)
        mode="key"
        key="$1"
        ;;
esac

path="$(orch_question_path "$id")"
if [ ! -f "$path" ]; then
    echo "ERROR: id '$id' 에 해당하는 질문 파일 없음 ($path)" >&2
    exit 2
fi

status="$(jq -r '.status' "$path")"
if [ "$status" = "answered" ]; then
    echo "ERROR: '$id' 는 이미 답변됨. 새 결정이 필요하면 orch 가 새 질문 등록." >&2
    echo "  기존 답변:" >&2
    jq -r '"    key: \(.answer.key // "(freeform)")\n    text: \(.answer.text // "")\n    ts: \(.answer.ts // "")"' "$path" >&2
    exit 2
fi

# key 모드: 옵션에 그 키가 있는지 검증
if [ "$mode" = "key" ]; then
    if ! jq -e --arg k "$key" '.options | map(.key) | index($k)' "$path" >/dev/null; then
        valid="$(jq -r '[.options[].key] | join(", ")' "$path")"
        echo "ERROR: key '$key' 가 이 질문의 옵션에 없음. 사용 가능: ${valid:-(없음 — --text 로 자유 답변)}" >&2
        exit 2
    fi
    label="$(jq -r --arg k "$key" '.options[] | select(.key == $k) | .label' "$path")"
fi

# text 모드: allow_freeform 검증
if [ "$mode" = "text" ]; then
    if [ "$(jq -r '.allow_freeform' "$path")" != "true" ]; then
        echo "ERROR: 이 질문은 allow_freeform=false. 옵션 key 로만 답변 가능 ('--text' 사용 불가)." >&2
        echo "  사용 가능 key: $(jq -r '[.options[].key] | join(", ")' "$path")" >&2
        exit 2
    fi
fi

ts="$(date -Iseconds)"

# 파일에 answer 채우고 status=answered
tmp="${path}.tmp.$$"
if [ "$mode" = "key" ]; then
    jq --arg k "$key" --arg t "$ts" \
        '.status = "answered" | .answer = {key: $k, text: null, ts: $t}' \
        "$path" >"$tmp"
else
    jq --arg txt "$text" --arg t "$ts" \
        '.status = "answered" | .answer = {key: null, text: $txt, ts: $t}' \
        "$path" >"$tmp"
fi
mv "$tmp" "$path"

# orch inbox 메시지
ctx="$(jq -r '.from_context // ""' "$path")"
if [ "$mode" = "key" ]; then
    body="[answer ${id}] key=${key} (${label})

context: ${ctx}"
else
    body="[answer ${id}] freeform

context: ${ctx}

${text}"
fi

msg_id="$(orch_append_message "user" "orch" "$body")"
orch_notify "orch" "$msg_id" || true

echo "OK [$id] answered → orch inbox (msg=$msg_id)"
if [ "$mode" = "key" ]; then
    echo "  key:   $key ($label)"
else
    echo "  text:  $text"
fi
echo "  path:  $path"
