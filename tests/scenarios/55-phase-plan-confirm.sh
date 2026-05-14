#!/usr/bin/env bash
# Phase plan 컨펌은 leader 가 직접 AskUserQuestion 으로 받고,
# 내부 결정은 [plan-confirm] / [plan-revise] / [plan-cancel] 세 라벨 중 하나여야 한다.
#
# - commands/check-inbox.md 에 옛 orch 중계 phase-plan 처리 절차가 없어야 함
# - scripts/issues/issue-up.sh 의 leader first_msg 가 AskUserQuestion 직접 컨펌 흐름 안내

set -euo pipefail

src_up="$PLUGIN_ROOT/scripts/issues/issue-up.sh"
skill_leader="$PLUGIN_ROOT/skills/orch-leader/SKILL.md"

[ -f "$src_up" ] || { echo "FAIL: $src_up 없음" >&2; exit 1; }
[ -f "$skill_leader" ] || { echo "FAIL: $skill_leader 없음" >&2; exit 1; }

src_inbox="$PLUGIN_ROOT/commands/check-inbox.md"
[ -f "$src_inbox" ] || { echo "FAIL: $src_inbox 없음" >&2; exit 1; }
if grep -q '특수 라벨 처리 — `\\[phase-plan' "$src_inbox"; then
    echo "FAIL: check-inbox.md 에 옛 orch 중계 phase-plan 처리 섹션 잔존" >&2
    exit 1
fi

for token in '[plan-confirm]' 'AskUserQuestion'; do
    if ! grep -qF "$token" "$src_up"; then
        echo "FAIL: issue-up.sh first_msg 에 hard guard '${token}' 없음" >&2; exit 1
    fi
done

# orch-leader SKILL — 직접 컨펌 + 3 라벨 분기 완전성
for token in '사용자 직접 컨펌' 'AskUserQuestion' '[plan-confirm]' '[plan-revise]' '[plan-cancel]'; do
    if ! grep -qF "$token" "$skill_leader"; then
        echo "FAIL: orch-leader SKILL 에 '${token}' 컨펌 흐름 없음" >&2; exit 1
    fi
done

# GO 받기 전 spawn 금지 명시 — first_msg 의 hard guard
if ! grep -q 'plan-confirm.*GO.*받기 전' "$src_up"; then
    echo "FAIL: issue-up.sh 에 'plan-confirm GO 받기 전 spawn 금지' hard guard 없음" >&2; exit 1
fi

echo "OK phase-plan-confirm"
