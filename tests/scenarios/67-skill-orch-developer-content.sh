#!/usr/bin/env bash
# Regression guard: orch-developer-worker SKILL.md 가 developer 페르소나·HOLD
# 체크포인트·차단 질문·PR 4단계·shutdown 을 담는지.

set -euo pipefail

skill="$PLUGIN_ROOT/skills/orch-developer-worker/SKILL.md"
[ -f "$skill" ] || { echo "FAIL: $skill 없음" >&2; exit 1; }

if ! awk '/^---$/{c++} c==1 && /^name: orch-developer-worker$/{found_name=1} c==1 && /^description:/{found_desc=1} END{exit !(found_name && found_desc)}' "$skill"; then
    echo "FAIL: orch-developer-worker SKILL frontmatter (name / description) 누락" >&2
    exit 1
fi

required=(
    "분석 우선"
    "최소 침습"
    "Surgical"
    "Simplicity"
    "leader"
    "/orch:check-inbox"
    "wait-reply.sh"
    "[question:"
    "worker-shutdown.sh"
    "gh pr"
    "wait-merge.sh"
    "coding-guidelines.md"
    "Design-first Task Graph"
    "developer_pr_v1"
    "workflow step"
    "hold_before_edit"
    "hold_before_push"
    "brief_validation"
    "push_and_pr"
    "ci"
    "ready_for_review"
    "wait_merge"
    "순서 invariant"
    "Task Graph"
)
missing=()
for phrase in "${required[@]}"; do
    if ! grep -qF "$phrase" "$skill"; then
        missing+=("$phrase")
    fi
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "FAIL: orch-developer-worker SKILL 에 다음 문구 누락:"
    printf '  - %s\n' "${missing[@]}"
    exit 1
fi

# HOLD 체크포인트 — 분석→편집 / push 직전 2 mark
if ! grep -q 'HOLD' "$skill"; then
    echo "FAIL: orch-developer-worker SKILL 에 'HOLD' 체크포인트 안내 없음" >&2
    exit 1
fi
if ! grep -qE '분석 → 편집|편집 전환' "$skill"; then
    echo "FAIL: orch-developer-worker SKILL 에 '분석 → 편집 전환' HOLD 안내 없음" >&2
    exit 1
fi
if ! grep -q 'push 직전' "$skill"; then
    echo "FAIL: orch-developer-worker SKILL 에 'push 직전' HOLD 안내 없음" >&2
    exit 1
fi

# 공통 운영 규약 단일 source 포인터
if ! grep -qF 'references/orch-protocols.md' "$skill"; then
    echo "FAIL: orch-developer-worker SKILL 이 references/orch-protocols.md 포인터를 갖지 않음" >&2
    exit 1
fi

echo "OK skill-orch-developer-content"
