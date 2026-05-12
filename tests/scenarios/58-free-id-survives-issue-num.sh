#!/usr/bin/env bash
# Regression guard: issue-up.sh / review-spawn.sh 가 숫자 없는 자유 식별자
# (예: feature-x, MP-onboarding) 를 leader_id 로 받아도 set -euo pipefail 아래에서
# id 파싱 단계에서 죽지 않아야 한다.
#
# 0.13.0~ 자유 식별자 정책: [A-Za-z0-9_-]+ 대소문자 보존.
# GitHub Issues 분기만 전체 숫자 검증을 통과해야 — issue-up.sh 가 명시 에러로 차단.
# GitLab fallback / Linear / Jira / none 분기는 자유 id 그대로 통과.

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

# 3. GitHub 전체 숫자 검증 — bash regex 로 부분 매칭이 아닌 ^[0-9]+$ 전체 매칭
out_full="$(
    set -euo pipefail
    test_id() {
        local mp_id="$1"
        if [[ "$mp_id" =~ ^[0-9]+$ ]]; then
            printf 'ok '
        else
            printf 'reject '
        fi
    }
    test_id "142"
    test_id "feature-2026"
    test_id "MP-13"
    test_id "0"
    test_id ""
)"
# 142=ok / feature-2026=reject (전체 숫자 아님) / MP-13=reject / 0=ok / 빈=reject
case "$out_full" in
    "ok reject reject ok reject ") : ;;
    *) echo "FAIL: github 전체 숫자 정규식 동작 불일치 — got: '$out_full'" >&2; exit 1 ;;
esac

# 4. issue-up.sh 가 github + 비숫자 id 에 대해 명시 에러로 차단하는 문구를 가지는지
if ! grep -q '전체 숫자 issue 번호가 아님' "$src_up"; then
    echo "FAIL: issue-up.sh 에 github + 비숫자 id 명시 에러 분기 없음" >&2
    exit 1
fi

# 5. review-spawn.sh 의 github 분기가 비숫자 id 일 때 lookup 생략 fallback 안내를
#    제공해야 (깨진 'gh issue view ' 호출 차단)
if ! grep -q "전체 숫자 id 가 아님" "$src_rev"; then
    echo "FAIL: review-spawn.sh github + 비숫자 id fallback 안내 누락" >&2
    exit 1
fi

echo "OK free-id-survives-issue-num"
