#!/usr/bin/env bash
# Regression guard: issue-up.sh 3 트래커 분기 fetch 실패 시 fuzzy fallback 안내 +
# SKILL.md §1.1 의 fuzzy fallback 프로토콜 (search → leader 직접 사용자 질문) 존재.
#
# 정책: leader 가 primary fetch 실패 시 임의 spawn 진행 금지, 트래커 search 로 후보 N 건
# 수집 → leader 가 AskUserQuestion 으로 사용자 결정 받고 진행.

set -euo pipefail

src_up="$PLUGIN_ROOT/scripts/issues/issue-up.sh"
provider_dir="$PLUGIN_ROOT/scripts/providers/issue-tracker"
skill="$PLUGIN_ROOT/skills/orch-leader/SKILL.md"

[ -f "$src_up" ] || { echo "FAIL: $src_up 없음" >&2; exit 1; }
[ -d "$provider_dir" ] || { echo "FAIL: $provider_dir 없음" >&2; exit 1; }
[ -f "$skill" ]  || { echo "FAIL: $skill 없음" >&2; exit 1; }

# 1. issue-up.sh 의 4 트래커 분기 모두 fuzzy fallback 진입 안내를 포함해야 한다.
declare -A fuzzy_marker=(
    [linear]="list_issues"
    [github]="gh issue list --search"
    [gitlab]="glab issue list --search"
)

for tracker in linear github gitlab; do
    file="$provider_dir/$tracker.sh"
    [ -f "$file" ] || { echo "FAIL: issue-tracker provider 없음: $file" >&2; exit 1; }
    block="$(cat "$file")"
    if [ -z "$block" ]; then
        echo "FAIL: issue-up.sh 에 ${tracker} case 블록 추출 실패" >&2
        exit 1
    fi
    if ! grep -qF "${fuzzy_marker[$tracker]}" <<<"$block"; then
        echo "FAIL: issue-up.sh ${tracker} 분기에 fuzzy 명령 '${fuzzy_marker[$tracker]}' 안내 누락" >&2
        exit 1
    fi
    if ! grep -qE 'fuzzy|fallback' <<<"$block"; then
        echo "FAIL: issue-up.sh ${tracker} 분기에 fuzzy/fallback 키워드 누락" >&2
        exit 1
    fi
done

if grep -q 'jira issue' "$src_up"; then
    echo "FAIL: issue-up.sh 에 제거된 jira fuzzy fallback 안내 잔존" >&2
    exit 1
fi

# 2. SKILL.md §1.1 — fuzzy fallback 프로토콜 필수 요소 포함.
required_skill_phrases=(
    "fetch 실패 fallback"
    "AskUserQuestion"
    "후보 선택"
    "다른 ID"
    "취소"
)
content="$(cat "$skill")"
missing=()
for phrase in "${required_skill_phrases[@]}"; do
    if ! grep -qF "$phrase" <<<"$content"; then
        missing+=("$phrase")
    fi
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "FAIL: SKILL.md §1.1 fuzzy fallback 절에 다음 필수 문구 누락:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    exit 1
fi

# 3. SKILL.md 의 fuzzy 절은 §1 셋업 안에 위치 — §2 작업 타입 판별 이전.
sec1_line="$(grep -n '^## 1\. 셋업' "$skill" | head -1 | cut -d: -f1)"
sec2_line="$(grep -n '^## 2\. 작업 타입 판별' "$skill" | head -1 | cut -d: -f1)"
fuzzy_line="$(grep -n 'fetch 실패 fallback' "$skill" | head -1 | cut -d: -f1)"
if [ -z "$sec1_line" ] || [ -z "$sec2_line" ] || [ -z "$fuzzy_line" ]; then
    echo "FAIL: SKILL.md 의 §1 / §2 / fuzzy 절 라인 검색 실패 (sec1=$sec1_line sec2=$sec2_line fuzzy=$fuzzy_line)" >&2
    exit 1
fi
if [ "$fuzzy_line" -le "$sec1_line" ] || [ "$fuzzy_line" -ge "$sec2_line" ]; then
    echo "FAIL: fuzzy fallback 절이 §1 셋업 안에 있지 않음 (sec1=$sec1_line, fuzzy=$fuzzy_line, sec2=$sec2_line)" >&2
    exit 1
fi

echo "OK issue-up-fuzzy-fallback"
