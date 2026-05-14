#!/usr/bin/env bash
# Regression guard: issue-up.sh / review-spawn.sh 의 자유 식별자 (예: feature-x,
# MP-onboarding) 처리. sanitize 정책 변경 (positive regex 폐지, deny-list 만) 이후:
# - issue-up.sh 가 사전 차단을 하지 않음 (트래커별 형식 검증은 leader fuzzy fallback 에 위임).
# - GitLab fallback 의 첫 숫자 추출은 set -euo pipefail 아래에서 '|| true' 안전 패턴 유지.
# - review-spawn.sh 의 github 분기는 자유 id 일 때 PR description 으로 판단하는 fallback 안내.

set -euo pipefail

src_up="$PLUGIN_ROOT/scripts/issue-up.sh"
src_rev="$PLUGIN_ROOT/scripts/review-spawn.sh"

[ -f "$src_up" ]  || { echo "FAIL: $src_up 없음" >&2; exit 1; }
[ -f "$src_rev" ] || { echo "FAIL: $src_rev 없음" >&2; exit 1; }

# 1. GitLab fallback 의 첫 숫자 추출은 '|| true' 안전 패턴이어야 (pipefail 사고 방지)
for f in "$src_up" "$src_rev"; do
    if ! grep -qE "grep -Eo '\[0-9\]\+' \| head -1 \|\| true" "$f"; then
        echo "FAIL: $f 에 '|| true' 안전 패턴 누락 — pipefail 아래 grep 실패 → 스크립트 종료 위험" >&2
        exit 1
    fi
done

# 2. 동적: 자유 식별자로 같은 패턴이 set -euo pipefail 아래에서 살아남는지
out_empty="$(
    set -euo pipefail
    mp_id="feature-onboarding"
    issue_num="$(printf '%s' "$mp_id" | grep -Eo '[0-9]+' | head -1 || true)"
    printf 'rc=%d issue_num=[%s]' "$?" "$issue_num"
)"
case "$out_empty" in
    "rc=0 issue_num=[]") : ;;
    *) echo "FAIL: 자유 식별자에서 빈 issue_num 안전 추출 실패 — got: $out_empty" >&2; exit 1 ;;
esac

# 3. issue-up.sh 는 GitHub 사전 차단을 하지 않음 (sanitize 만 통과하면 spawn) —
#    트래커 형식 검증 / fetch 실패는 leader fuzzy fallback 에 위임.
if grep -q '전체 숫자 issue 번호가 아님' "$src_up"; then
    echo "FAIL: issue-up.sh 에 stale 한 GitHub 사전 차단 메시지 잔존 (fuzzy fallback 정책과 충돌)" >&2
    exit 1
fi

# 4. review-spawn.sh 의 github 분기가 자유 id 일 때 PR description 으로 판단하는
#    fallback 메시지 유지 (PR 리뷰 컨텍스트라 fuzzy 가 아닌 description 기반 판단).
if ! grep -q "전체 숫자 id 가 아님" "$src_rev"; then
    echo "FAIL: review-spawn.sh github + 자유 id fallback 안내 누락" >&2
    exit 1
fi

echo "OK free-id-survives-issue-num"
