#!/usr/bin/env bash
# Regression guard: orch-reviewer SKILL.md 가 read-only / 두 채널 답신 / verdict 형식 /
# shutdown 을 담는지.

set -euo pipefail

skill="$PLUGIN_ROOT/skills/orch-reviewer/SKILL.md"
[ -f "$skill" ] || { echo "FAIL: $skill 없음" >&2; exit 1; }

if ! awk '/^---$/{c++} c==1 && /^name: orch-reviewer$/{found_name=1} c==1 && /^description:/{found_desc=1} END{exit !(found_name && found_desc)}' "$skill"; then
    echo "FAIL: orch-reviewer SKILL frontmatter (name / description) 누락" >&2
    exit 1
fi

required=(
    "reviewer"
    "읽기 전용"
    "gh pr diff"
    "gh pr comment"
    "leader"
    "두 채널"
    "[review PR #"
    "LGTM"
    "needs-changes"
    "worker-shutdown.sh"
    "coding-guidelines.md"
    "Design-first Task Graph"
    "reviewer_pr_v1"
    "workflow step"
    "respond"
    "acceptance criteria"
    "depends_on"
    "Task Graph"
    "first_msg"
    "task-graph.json"
)
missing=()
for phrase in "${required[@]}"; do
    if ! grep -qF "$phrase" "$skill"; then
        missing+=("$phrase")
    fi
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "FAIL: orch-reviewer SKILL 에 다음 문구 누락:"
    printf '  - %s\n' "${missing[@]}"
    exit 1
fi

# 수정/커밋/push 금지 명시
if ! grep -qE '코드 수정.*금지|수정.*커밋.*push.*금지' "$skill"; then
    echo "FAIL: orch-reviewer SKILL 에 '코드 수정·커밋·push 금지' 명시 없음" >&2
    exit 1
fi

# 본 PR 변경분 범위 제한
if ! grep -qE 'PR 변경분|본 PR' "$skill"; then
    echo "FAIL: orch-reviewer SKILL 에 'PR 변경분 범위' 제한 안내 없음" >&2
    exit 1
fi

# 공통 운영 규약 단일 source 포인터
if ! grep -qF 'references/orch-protocols.md' "$skill"; then
    echo "FAIL: orch-reviewer SKILL 이 references/orch-protocols.md 포인터를 갖지 않음" >&2
    exit 1
fi

echo "OK skill-orch-reviewer-content"
