#!/usr/bin/env bash
# /orch:inbox-prune [--dry-run]
# 누적된 orphan inbox 파일 일괄 청소 — issue-down 에서 정리 빠진 과거 leader 의
# .orch/inbox/mp-NN.md + .lock 제거. 살아있는 leader (workers/<mp-NN>.json 등록)
# 의 inbox 는 건드리지 않음.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/dev/null
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

dry_run=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run=1 ;;
        -h|--help)
            cat <<EOF
사용법: /orch:inbox-prune [--dry-run]
  살아있지 않은 leader 의 inbox/mp-NN.md + .lock 일괄 제거.
  --dry-run: 실제 삭제 없이 후보만 표시.
EOF
            exit 0 ;;
        *) echo "ERROR: 알 수 없는 옵션: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ ! -d "$ORCH_INBOX" ]; then
    echo "INBOX_EMPTY (디렉토리 없음: $ORCH_INBOX)"
    exit 0
fi

shopt -s nullglob
files=( "$ORCH_INBOX"/mp-*.md )
shopt -u nullglob

if [ "${#files[@]}" -eq 0 ]; then
    echo "정리 대상 없음 (mp-*.md 파일 0건)"
    exit 0
fi

orphans=()
active=()
for f in "${files[@]}"; do
    base="$(basename "$f" .md)"
    reg="$ORCH_WORKERS/$base.json"
    if [ -f "$reg" ]; then
        active+=("$base")
    else
        orphans+=("$base")
    fi
done

echo "── /orch:inbox-prune ──"
echo "전체:   ${#files[@]}건"
echo "active: ${#active[@]}건${active[*]+ (${active[*]})}"
echo "orphan: ${#orphans[@]}건"

if [ "${#orphans[@]}" -eq 0 ]; then
    echo "✅ 청소할 orphan 없음"
    exit 0
fi

for o in "${orphans[@]}"; do
    f="$ORCH_INBOX/$o.md"
    lock="${f}.lock"
    size="$(wc -c <"$f" 2>/dev/null || echo ?)"
    if [ "$dry_run" -eq 1 ]; then
        echo "  [dry-run] $f (${size} bytes) + ${lock}"
    else
        rm -f "$f" "$lock"
        echo "  removed $o (${size} bytes)"
    fi
done

if [ "$dry_run" -eq 1 ]; then
    echo
    echo "(--dry-run — 실제 삭제 없음. 위 목록을 실행하려면 --dry-run 빼고 다시.)"
else
    echo
    echo "✅ orphan ${#orphans[@]}건 정리 완료"
fi
