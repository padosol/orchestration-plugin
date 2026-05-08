#!/usr/bin/env bash
# /orch:questions [<q-id>]
# - 인자 없음: open 상태 질문 목록 표 (id, ts, context, question 첫 50자)
# - <q-id> 지정: 단건 본문 + 선택지 출력 (사용자가 선택할 때 본다)

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/dev/null
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

if [ ! -d "$ORCH_QUESTIONS" ]; then
    echo "QUESTIONS_EMPTY (디렉토리 없음 — orch 가 아직 ask 한 적 없음)"
    exit 0
fi

if [ "$#" -ge 1 ] && [ -n "${1:-}" ]; then
    # 단건 모드
    id="$1"
    path="$(orch_question_path "$id")"
    if [ ! -f "$path" ]; then
        echo "ERROR: id '$id' 에 해당하는 질문 파일 없음 ($path)" >&2
        exit 2
    fi
    status="$(jq -r '.status' "$path")"
    ctx="$(jq -r '.from_context // ""' "$path")"
    q="$(jq -r '.question // ""' "$path")"
    ts="$(jq -r '.ts // ""' "$path")"
    allow_freeform="$(jq -r '.allow_freeform // false' "$path")"

    echo "=== QUESTION $id ==="
    echo "status:         $status"
    echo "context:        $ctx"
    echo "ts:             $ts"
    echo "allow_freeform: $allow_freeform"
    echo
    echo "── 본문 ──"
    printf '%s\n' "$q"
    echo
    echo "── 선택지 ──"
    if [ "$(jq '.options | length' "$path")" = "0" ]; then
        echo "(없음 — 자유 텍스트 답변만)"
    else
        jq -r '.options[] | "  \(.key)\t\(.label)"' "$path"
    fi

    if [ "$status" = "answered" ]; then
        echo
        echo "── 답변 ──"
        jq -r '.answer | "  key:  \(.key // "(freeform)")\n  text: \(.text // "")\n  ts:   \(.ts // "")"' "$path"
    else
        echo
        if [ "$allow_freeform" = "true" ]; then
            echo "답변: \$ORCH_BIN_DIR/answer.sh $id <key>      또는"
            echo "      \$ORCH_BIN_DIR/answer.sh $id --text \"<자유 답변>\""
        else
            echo "답변: \$ORCH_BIN_DIR/answer.sh $id <key>"
        fi
    fi
    exit 0
fi

# 목록 모드 — open 만 (answered 는 questions/<id>.json 에 그대로 있되 표에서 숨김)
shopt -s nullglob
files=( "$ORCH_QUESTIONS"/*.json )
shopt -u nullglob

open_count=0
for f in "${files[@]+"${files[@]}"}"; do
    [ -f "$f" ] || continue
    if [ "$(jq -r '.status' "$f" 2>/dev/null)" = "open" ]; then
        open_count=$((open_count + 1))
    fi
done

answered_count=$((${#files[@]} - open_count))

if [ "$open_count" -eq 0 ]; then
    if [ "$answered_count" -gt 0 ]; then
        echo "QUESTIONS_EMPTY (open 0건, answered $answered_count건은 보존됨 — \$ORCH_BIN_DIR/questions.sh <id> 로 열람 가능)"
    else
        echo "QUESTIONS_EMPTY (등록된 질문 없음)"
    fi
    exit 0
fi

echo "=== QUESTIONS open=$open_count answered=$answered_count ==="
printf 'id\tts\tcontext\tquestion-50\n'
# 최신 위 정렬 (ts desc)
for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    [ "$(jq -r '.status' "$f" 2>/dev/null)" = "open" ] || continue
    jq -r '"\(.id)\t\(.ts)\t\(.from_context // "")\t\((.question // "") | gsub("\n"; " ") | .[0:50])"' "$f"
done | sort -t$'\t' -k2,2r
echo
echo "▶ 단건 보기: \$ORCH_BIN_DIR/questions.sh <id>"
echo "  답변: \$ORCH_BIN_DIR/answer.sh <id> <key>  (또는 --text \"...\")"
