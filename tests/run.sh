#!/usr/bin/env bash
# orch-plugin 자동 회귀 테스트 — 격리 sandbox 에서 hook / 스크립트 시나리오 일괄 실행.
#
# 사용: bash tests/run.sh [scenario-name ...]
#   인자 없으면 tests/scenarios/*.sh 전부 실행. 이름 지정하면 해당 시나리오만.
#
# 환경 가정:
#   - PLUGIN_ROOT = 이 스크립트 부모 (source tree). marketplace 캐시·plugin install 불필요.
#   - SANDBOX = tests/sandbox/ (매 실행마다 wipe). 각 시나리오가 자기 하위 디렉토리에 fixture 생성.
#
# 시나리오 컨트랙트:
#   stdin 비어있음. stdout/stderr 자유. exit 0 = PASS, 그 외 = FAIL.
#   환경변수 PLUGIN_ROOT, SANDBOX 제공. 시나리오는 set -euo pipefail 권장.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$TESTS_DIR")"
SANDBOX="${TESTS_DIR}/sandbox"
LOG="${TESTS_DIR}/.last-run.log"

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"
: > "$LOG"

if [ "$#" -gt 0 ]; then
    targets=()
    for name in "$@"; do
        path="$TESTS_DIR/scenarios/${name}.sh"
        if [ ! -f "$path" ]; then
            echo "ERROR: 시나리오 '$name' 없음 ($path)" >&2
            exit 2
        fi
        targets+=("$path")
    done
else
    mapfile -t targets < <(ls "$TESTS_DIR"/scenarios/*.sh 2>/dev/null | sort)
fi

if [ "${#targets[@]}" -eq 0 ]; then
    echo "ERROR: 실행할 시나리오 없음 ($TESTS_DIR/scenarios/)" >&2
    exit 2
fi

pass=0
fail=0
failed_names=()

for scenario in "${targets[@]}"; do
    name="$(basename "$scenario" .sh)"
    printf '[scenario] %-30s ... ' "$name"
    {
        echo
        echo "=== $name ==="
        date '+%Y-%m-%dT%H:%M:%S'
    } >> "$LOG"
    if PLUGIN_ROOT="$PLUGIN_ROOT" SANDBOX="$SANDBOX" bash "$scenario" >> "$LOG" 2>&1; then
        pass=$((pass + 1))
        echo "PASS"
    else
        fail=$((fail + 1))
        failed_names+=("$name")
        echo "FAIL"
    fi
done

echo "─────────────────────────────"
echo "Total: pass=$pass fail=$fail"
if [ "$fail" -gt 0 ]; then
    echo "Failed: ${failed_names[*]}"
    echo "Log: $LOG (tail 위해 'tail -100 $LOG' 권장)"
    exit 1
fi
echo "Log: $LOG"
