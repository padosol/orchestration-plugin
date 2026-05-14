#!/usr/bin/env bash
# Regression guard: Phase 1~3 가 안 다룬 헤더 주석 / commands 문서의 잔존 gh 단독 표기
# 차단. 모든 host CLI 안내는 (a) 양 표기 (gh + glab) 또는 (b) 추상 표현 (호스트 PR/MR /
# first_msg <pr_*_cmd> 변수) 중 하나여야 함.

set -euo pipefail

review_spawn_sh="$PLUGIN_ROOT/scripts/review-spawn.sh"
review_spawn_md="$PLUGIN_ROOT/commands/review-spawn.md"
issue_down_md="$PLUGIN_ROOT/commands/issue-down.md"

for f in "$review_spawn_sh" "$review_spawn_md" "$issue_down_md"; do
    [ -f "$f" ] || { echo "FAIL: $f 없음" >&2; exit 1; }
done

# 1. scripts/review-spawn.sh 헤더 주석 (line 1~10) 에 stale 'gh pr diff/view ... GitHub PR
#    코멘트' 직결 단독 표기 잔존 금지. <pr_*_cmd> 변수 또는 host-neutral 표현 사용.
header_sh="$(head -10 "$review_spawn_sh")"
if grep -qE 'gh pr (diff|view).*GitHub PR' <<<"$header_sh"; then
    echo "FAIL: review-spawn.sh 헤더 주석에 stale 한 'gh pr diff/view ... GitHub PR' 단독 표기 잔존" >&2
    exit 1
fi
# 헤더에 first_msg 변수 또는 호스트 추상 표현이 있어야
if ! grep -qE '<pr_.*_cmd>|호스트 PR/MR' <<<"$header_sh"; then
    echo "FAIL: review-spawn.sh 헤더 주석이 host-aware 표기 (변수 또는 '호스트 PR/MR') 누락" >&2
    exit 1
fi

# 2. commands/review-spawn.md: 'gh pr diff/view' 단독 표기 (glab 동반 없이) 차단
#    & 동작 절에 양 표기 (gh / glab) 함께 등장해야
line21_block="$(grep -n 'reviewer 가' "$review_spawn_md" | head -1)"
if [ -z "$line21_block" ]; then
    echo "FAIL: commands/review-spawn.md 의 'reviewer 가' 안내 라인 없음" >&2; exit 1
fi
# 동작 절 안에 gh 와 glab 동시 등장 확인
review_md_action_block="$(awk '/^4\. reviewer/{print; getline; while ($0 !~ /^$/) {print; getline}}' "$review_spawn_md")"
if [ -z "$review_md_action_block" ]; then
    # 단일 라인 케이스
    review_md_action_block="$(grep '^4\. reviewer' "$review_spawn_md")"
fi
if ! grep -q 'gh pr' <<<"$review_md_action_block"; then
    echo "FAIL: commands/review-spawn.md 의 reviewer 동작 안내에 'gh pr' 표기 누락 (양 표기 의무)" >&2
    exit 1
fi
if ! grep -q 'glab mr' <<<"$review_md_action_block"; then
    echo "FAIL: commands/review-spawn.md 의 reviewer 동작 안내에 'glab mr' 표기 누락 (양 표기 의무)" >&2
    exit 1
fi

# 3. commands/issue-down.md 의 머지 확인 / fallback / 안전장치 절에 host 양 표기 또는
#    orch_pr_merged_by_branch 헬퍼 언급
issue_down_content="$(cat "$issue_down_md")"
# 머지 확인 라인 — gh pr list + glab mr list 둘 다 또는 헬퍼 추상화
if ! grep -qE 'gh pr list.*glab mr list|glab mr list.*gh pr list|orch_pr_merged_by_branch' <<<"$issue_down_content"; then
    echo "FAIL: commands/issue-down.md 의 머지 확인 안내에 'gh + glab 양 표기' 또는 'orch_pr_merged_by_branch' 헬퍼 누락" >&2
    exit 1
fi
# stale 'gh / git 양쪽' 표현 잔존 금지 (호스트 CLI 가 gh|glab 둘 다 가능)
if grep -qE '^\s*-\s*gh / git 양쪽' "$issue_down_md"; then
    echo "FAIL: commands/issue-down.md 에 stale 한 'gh / git 양쪽' 표기 잔존 (호스트 CLI 표기로 수정 필요)" >&2
    exit 1
fi

echo "OK host-neutral-docs"
