#!/usr/bin/env bash
# Regression guard: orch-pm SKILL.md 가 PM 페르소나·책임·direction-check + wait-reply
# 차단 패턴을 담는지. first_msg 에는 hard guard 만 남음.

set -euo pipefail

skill="$PLUGIN_ROOT/skills/orch-pm/SKILL.md"
[ -f "$skill" ] || { echo "FAIL: $skill 없음" >&2; exit 1; }

if ! awk '/^---$/{c++} c==1 && /^name: orch-pm$/{found_name=1} c==1 && /^description:/{found_desc=1} END{exit !(found_name && found_desc)}' "$skill"; then
    echo "FAIL: orch-pm SKILL frontmatter (name / description) 누락" >&2
    exit 1
fi

required=(
    "PM"
    "시스템 아키텍트"
    "분석"
    "설계"
    "direction-check"
    "wait-reply.sh"
    "[question:"
    "[reply:"
    "docs/spec/"
    "leader"
    "사용자 컨펌"
    "phase"
    "API"
    "Design-first Task Graph"
    "proposed_task_graph"
    "approved_task_graph"
    "제안자"
    "최종 확정자"
    "Proposed Task Graph"
    "proposed-task-graph.json"
    "pm_design_v1"
)
missing=()
for phrase in "${required[@]}"; do
    if ! grep -qF "$phrase" "$skill"; then
        missing+=("$phrase")
    fi
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "FAIL: orch-pm SKILL 에 다음 문구 누락:"
    printf '  - %s\n' "${missing[@]}"
    exit 1
fi

# direct 통신 금지 (developer/reviewer 와 직접 통신 금지)
if ! grep -qE 'developer.*직접 통신|직접 통신.*developer|hub-and-spoke|허브' "$skill"; then
    echo "FAIL: orch-pm SKILL 에 'developer/reviewer 직접 통신 금지' 안내 없음" >&2
    exit 1
fi

# 공통 운영 규약 단일 source 포인터
if ! grep -qF 'references/orch-protocols.md' "$skill"; then
    echo "FAIL: orch-pm SKILL 이 references/orch-protocols.md 포인터를 갖지 않음" >&2
    exit 1
fi

# phase 소유는 leader — PM 은 산출물만
if ! grep -qE 'phase .*leader|leader .*phase' "$skill"; then
    echo "FAIL: orch-pm SKILL 에 'phase 계획·실행 순서는 leader 가 소유' 안내 없음" >&2
    exit 1
fi

echo "OK skill-orch-pm-content"
