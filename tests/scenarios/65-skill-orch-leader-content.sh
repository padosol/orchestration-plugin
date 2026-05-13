#!/usr/bin/env bash
# Regression guard: orch-leader SKILL.md 가 leader 페르소나·임무·절차를 모두 담는지.
# first_msg 에서 detail 본문은 빠졌으므로 SKILL 이 단일 source.

set -euo pipefail

skill="$PLUGIN_ROOT/skills/orch-leader/SKILL.md"
[ -f "$skill" ] || { echo "FAIL: $skill 없음" >&2; exit 1; }

# 1. frontmatter — Skill 도구가 invoke 결정에 쓰는 description / name
if ! awk '/^---$/{c++} c==1 && /^name: orch-leader$/{found_name=1} c==1 && /^description:/{found_desc=1} END{exit !(found_name && found_desc)}' "$skill"; then
    echo "FAIL: orch-leader SKILL frontmatter (name / description) 누락" >&2
    exit 1
fi

# 2. 페르소나 — 팀리더 책임
required=(
    "팀리더"
    "phase plan"
    "phases.md"
    "Phase 1"
    "[phase-plan"
    "[plan-confirm]"
    "[plan-revise]"
    "[plan-cancel]"
    "[type-clarify:"
    "[type-decision:"
    "[reply:"
    "wait-reply.sh"
    "Phase 0"
    "분석/설계"
    "direction-check"
    "[follow-up-candidates"
    "issue-down"
    "report.sh"
    "REPORT-data.md"
    "Design-first Task Graph"
    "task-graph.json"
    "approved_task_graph"
    "depends_on"
    "ready task"
    "placeholder template"
    "task graph 승인 전"
)
missing=()
for phrase in "${required[@]}"; do
    if ! grep -qF "$phrase" "$skill"; then
        missing+=("$phrase")
    fi
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "FAIL: orch-leader SKILL 에 다음 문구 누락:"
    printf '  - %s\n' "${missing[@]}"
    exit 1
fi

# 3. 공통 운영 규약은 orch-protocols.md 로 위임 — SKILL 본문에 protocols 포인터 있어야
if ! grep -qF 'references/orch-protocols.md' "$skill"; then
    echo "FAIL: orch-leader SKILL 이 references/orch-protocols.md 포인터를 갖지 않음" >&2
    exit 1
fi

# 4. 옛 충돌 문구 잔존 금지
if grep -q 'PM 워커 먼저 spawn' "$skill"; then
    echo "FAIL: orch-leader SKILL 에 옛 'PM 워커 먼저 spawn' 잔존" >&2
    exit 1
fi

echo "OK skill-orch-leader-content"
