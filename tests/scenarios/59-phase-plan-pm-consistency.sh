#!/usr/bin/env bash
# Regression guard: issue-up.sh first_msg 안의 Phase Plan / PM spawn 문구가
# 충돌 (GO 전 PM 먼저 spawn vs GO 전 모든 워커 spawn 금지) 로 회귀하지 않도록.
#
# 정책: 사용자 [plan-confirm] GO 받기 전에는 PM 포함 어떤 워커도 spawn 금지.
#       PM 이 필요하면 phase plan 안에 "Phase 0: 분석/설계" 또는 첫 phase 로
#       명시하고 컨펌 후 그 phase 시작 시점에 spawn.

set -euo pipefail

src="$PLUGIN_ROOT/scripts/issue-up.sh"
[ -f "$src" ] || { echo "FAIL: $src 없음" >&2; exit 1; }

# 1. GO 전 PM 포함 모든 워커 spawn 금지 문구 존재
if ! grep -qF 'PM 포함 어떤 워커도 spawn 금지' "$src"; then
    echo "FAIL: 'PM 포함 어떤 워커도 spawn 금지' 문구 없음 — Phase Plan 충돌 재발" >&2
    exit 1
fi

# 2. Phase 0 분석/설계 흐름이 plan 단계에 포함되어야 (PM 이 plan 의 하위 phase 로)
if ! grep -q 'Phase 0' "$src"; then
    echo "FAIL: 'Phase 0' 분석/설계 흐름 안내 없음" >&2
    exit 1
fi
if ! grep -q '분석/설계' "$src"; then
    echo "FAIL: '분석/설계' phase 안내 없음" >&2
    exit 1
fi

# 3. 옛 충돌 문구 잔존 금지 — "PM 워커 먼저 spawn" 류는 plan 컨펌 전 spawn 흐름과 충돌
if grep -q 'PM 워커 먼저 spawn' "$src"; then
    echo "FAIL: 옛 'PM 워커 먼저 spawn' 지시 잔존 — phase plan 컨펌 전 spawn 흐름과 충돌" >&2
    exit 1
fi

# 4. [plan-confirm] GO 라벨이 'spawn 허가' 트리거로 명시되어야
if ! grep -q '\[plan-confirm\] GO' "$src"; then
    echo "FAIL: '[plan-confirm] GO' 트리거 라벨 안내 없음" >&2
    exit 1
fi

echo "OK phase-plan-pm-consistency"
