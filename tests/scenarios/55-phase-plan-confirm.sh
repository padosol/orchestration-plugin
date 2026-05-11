#!/usr/bin/env bash
# Phase plan 컨펌은 반드시 AskUserQuestion 으로 받고, leader 에 forward 하는
# 응답은 [plan-confirm] / [plan-revise] / [plan-cancel] 세 라벨 중 하나여야 한다.
#
# - commands/check-inbox.md 에 phase-plan 라벨 처리 절차 + AskUserQuestion 명시 + 세 라벨 모두 등장
# - scripts/issue-up.sh 의 leader first_msg 가 세 라벨 + AskUserQuestion 흐름 안내

set -euo pipefail

src_inbox="$PLUGIN_ROOT/commands/check-inbox.md"
src_up="$PLUGIN_ROOT/scripts/issue-up.sh"

[ -f "$src_inbox" ] || { echo "FAIL: $src_inbox 없음" >&2; exit 1; }
[ -f "$src_up" ] || { echo "FAIL: $src_up 없음" >&2; exit 1; }

# check-inbox.md — phase-plan 절 + AskUserQuestion + 3 라벨
for token in '[phase-plan' 'AskUserQuestion' '[plan-confirm]' '[plan-revise]' '[plan-cancel]'; do
    if ! grep -qF "$token" "$src_inbox"; then
        echo "FAIL: check-inbox.md 에 '${token}' 없음" >&2; exit 1
    fi
done

# 자유서술 답신 금지 명시 (plain text 답신 차단 의도)
if ! grep -q '자유서술' "$src_inbox"; then
    echo "FAIL: check-inbox.md 에 '자유서술 답신 금지' 안내 없음" >&2; exit 1
fi

# issue-up.sh — leader 가 세 라벨 + AskUserQuestion 흐름 인지
for token in '[plan-confirm]' '[plan-revise]' '[plan-cancel]' 'AskUserQuestion'; do
    if ! grep -qF "$token" "$src_up"; then
        echo "FAIL: issue-up.sh 에 '${token}' 없음" >&2; exit 1
    fi
done

# GO 받기 전 spawn 금지 명시
if ! grep -q 'plan-confirm.*GO.*받기 전' "$src_up"; then
    echo "FAIL: issue-up.sh 에 'plan-confirm GO 받기 전 spawn 금지' 안내 없음" >&2; exit 1
fi

echo "OK phase-plan-confirm"
