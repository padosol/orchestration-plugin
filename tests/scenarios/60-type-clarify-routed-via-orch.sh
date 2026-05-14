#!/usr/bin/env bash
# Regression guard: 작업 타입 모호 시 orch 중계 없이 leader 가 직접 AskUserQuestion 으로
# feature / bug / refactor 를 확정하는지 검증. SKILL 통합 후 절차 본문은 orch-leader
# SKILL.md 로 이동했으므로 first_msg 에는 hard guard, SKILL 본문에는 자세한 절차로 분리해 검사.

set -euo pipefail

src_up="$PLUGIN_ROOT/scripts/issues/issue-up.sh"
skill_leader="$PLUGIN_ROOT/skills/orch-leader/SKILL.md"
doc="$PLUGIN_ROOT/commands/check-inbox.md"

[ -f "$src_up" ]       || { echo "FAIL: $src_up 없음" >&2; exit 1; }
[ -f "$skill_leader" ] || { echo "FAIL: $skill_leader 없음" >&2; exit 1; }
[ -f "$doc" ]          || { echo "FAIL: $doc 없음" >&2; exit 1; }

# 1. first_msg hard guard — leader 직접 AskUserQuestion 흐름
if ! grep -qF '작업 타입 모호 시 leader 가 직접 AskUserQuestion 호출' "$src_up"; then
    echo "FAIL: issue-up.sh first_msg 에 leader 직접 AskUserQuestion hard guard 누락" >&2
    exit 1
fi

# 2. orch 중계 라벨 잔존 금지
for f in "$src_up" "$doc" "$skill_leader"; do
    if grep -qF '[type-decision:' "$f"; then
        echo "FAIL: $f 에 옛 '[type-decision:<qid>]' orch 중계 라벨 잔존" >&2
        exit 1
    fi
done
if grep -q '특수 라벨 처리 — `\\[type-clarify' "$doc"; then
    echo "FAIL: check-inbox.md 에 옛 type-clarify 처리 섹션 잔존" >&2
    exit 1
fi

# 3. orch-leader SKILL 본문 — feature / bug / refactor 3택 직접 확인
for token in 'leader 직접 확인' 'AskUserQuestion' 'feature' 'bug' 'refactor'; do
    if ! grep -qF "$token" "$skill_leader"; then
        echo "FAIL: orch-leader SKILL 에 타입 직접 확인 토큰 '${token}' 누락" >&2
        exit 1
    fi
done
if ! grep -qF 'wait-reply' "$skill_leader"; then
    echo "FAIL: orch-leader SKILL 에 worker wait-reply 규약까지 사라짐" >&2
    exit 1
fi

echo "OK type-clarify-direct-leader"
