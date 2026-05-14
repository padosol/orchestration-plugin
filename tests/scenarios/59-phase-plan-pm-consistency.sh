#!/usr/bin/env bash
# Regression guard: phase plan ↔ PM spawn 정책 (GO 전 PM 포함 spawn 금지) 가
# (a) first_msg 의 hard guard 와 (b) orch-leader SKILL 본문에 모두 일관되게 유지되는지.
# SKILL 통합 후 절차 본문은 SKILL 로 이동했으므로 양쪽 모두 검사.

set -euo pipefail

src="$PLUGIN_ROOT/scripts/issues/issue-up.sh"
skill="$PLUGIN_ROOT/skills/orch-leader/SKILL.md"
[ -f "$src" ]   || { echo "FAIL: $src 없음" >&2; exit 1; }
[ -f "$skill" ] || { echo "FAIL: $skill 없음" >&2; exit 1; }

# 1. first_msg 의 hard guard — GO 전 PM 포함 모든 워커 spawn 금지
if ! grep -qF 'PM 포함 어떤 워커도 spawn 금지' "$src"; then
    echo "FAIL: first_msg 에 'PM 포함 어떤 워커도 spawn 금지' hard guard 없음" >&2
    exit 1
fi
# 1-b. first_msg 의 hard guard — [plan-confirm] GO 라벨이 spawn 허가 트리거
if ! grep -qF '[plan-confirm] GO' "$src"; then
    echo "FAIL: first_msg 에 '[plan-confirm] GO' 트리거 라벨 안내 없음" >&2
    exit 1
fi

# 2. orch-leader SKILL 에 Phase 0 분석/설계 흐름이 명시되어야 (PM 이 plan 의 하위 phase 로)
if ! grep -q 'Phase 0' "$skill"; then
    echo "FAIL: orch-leader SKILL 에 'Phase 0' 분석/설계 흐름 안내 없음" >&2
    exit 1
fi
if ! grep -q '분석/설계' "$skill"; then
    echo "FAIL: orch-leader SKILL 에 '분석/설계' phase 안내 없음" >&2
    exit 1
fi

# 3. 옛 충돌 문구 잔존 금지 — 'PM 워커 먼저 spawn' 류는 plan 컨펌 전 spawn 흐름과 충돌
for f in "$src" "$skill"; do
    if grep -q 'PM 워커 먼저 spawn' "$f"; then
        echo "FAIL: $f 에 옛 'PM 워커 먼저 spawn' 지시 잔존 — phase plan 컨펌 전 spawn 흐름과 충돌" >&2
        exit 1
    fi
done

echo "OK phase-plan-pm-consistency"
