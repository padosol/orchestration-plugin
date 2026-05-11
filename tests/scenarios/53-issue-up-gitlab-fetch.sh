#!/usr/bin/env bash
# issue-up.sh / review-spawn.sh — tracker=gitlab 일 때 first_msg 에 glab issue view 자동 fetch 분기가
# 들어가는지 (jira 는 spec request fallback 유지).

set -euo pipefail

src_up="$PLUGIN_ROOT/scripts/issue-up.sh"
src_rev="$PLUGIN_ROOT/scripts/review-spawn.sh"
[ -f "$src_up" ] || { echo "FAIL: $src_up 없음"; exit 1; }
[ -f "$src_rev" ] || { echo "FAIL: $src_rev 없음"; exit 1; }

# issue-up.sh 안에 gitlab → glab 분기 / jira → spec request 분기가 분리돼 있는지
if ! grep -q 'gitlab)' "$src_up"; then
    echo "FAIL: issue-up.sh 에 'gitlab)' case 없음" >&2; exit 1
fi
if ! grep -q 'glab issue view' "$src_up"; then
    echo "FAIL: issue-up.sh 에 'glab issue view' 호출 없음" >&2; exit 1
fi
if ! grep -q 'jira)' "$src_up"; then
    echo "FAIL: issue-up.sh 에 'jira)' case 없음 (분리 누락)" >&2; exit 1
fi
# 옛 합쳐진 패턴 'jira|gitlab' 잔존 금지
if grep -q 'jira|gitlab' "$src_up"; then
    echo "FAIL: issue-up.sh 에 합쳐진 'jira|gitlab' case 잔존 — gitlab 만 자동 fetch 분기여야 함" >&2; exit 1
fi

# review-spawn.sh 도 동일 규칙
if ! grep -q 'gitlab)' "$src_rev"; then
    echo "FAIL: review-spawn.sh 에 'gitlab)' case 없음" >&2; exit 1
fi
if ! grep -q 'glab issue view' "$src_rev"; then
    echo "FAIL: review-spawn.sh 에 'glab issue view' 호출 없음" >&2; exit 1
fi
if grep -q 'jira|gitlab' "$src_rev"; then
    echo "FAIL: review-spawn.sh 에 합쳐진 'jira|gitlab' case 잔존" >&2; exit 1
fi

echo "OK issue-up-gitlab-fetch"
