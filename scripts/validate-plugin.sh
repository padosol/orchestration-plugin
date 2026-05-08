#!/usr/bin/env bash
# /orch:validate-plugin
# 플러그인 자체 위생 검증 — 문법(bash/python/json) + 종속어(절대경로 등) 검출.
# 플러그인 수정/추가 시 호출. setup 직후에도 자동 권유.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

PLUGIN_ROOT="$(dirname "$LIB_DIR")"

errors=0
warnings=0

echo "── /orch:validate-plugin ──"
echo "plugin_root: $PLUGIN_ROOT"
echo

# ── 1. bash 문법 ──────────────────────────────────────
echo "[1/4] bash 문법 검사"
fail=0
while IFS= read -r f; do
    err="$(bash -n "$f" 2>&1 || true)"
    if [ -n "$err" ]; then
        echo "  ❌ $f"
        printf '%s\n' "$err" | sed 's/^/      /'
        fail=$((fail + 1))
    fi
done < <(find "$PLUGIN_ROOT" \( -path '*/.git' -o -path '*/__pycache__' \) -prune -o -name '*.sh' -type f -print)
if [ "$fail" -eq 0 ]; then
    echo "  ✅ 모든 .sh 통과"
else
    errors=$((errors + fail))
fi

# ── 2. python 문법 ────────────────────────────────────
echo "[2/4] python 문법 검사"
fail=0
while IFS= read -r f; do
    if ! python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" 2>/tmp/orch-validate-py.err; then
        echo "  ❌ $f"
        sed 's/^/      /' /tmp/orch-validate-py.err
        fail=$((fail + 1))
    fi
done < <(find "$PLUGIN_ROOT" \( -path '*/.git' -o -path '*/__pycache__' \) -prune -o -name '*.py' -type f -print)
rm -f /tmp/orch-validate-py.err
if [ "$fail" -eq 0 ]; then
    echo "  ✅ 모든 .py 통과"
else
    errors=$((errors + fail))
fi

# ── 3. JSON 문법 ──────────────────────────────────────
echo "[3/4] JSON 문법 검사"
fail=0
while IFS= read -r f; do
    if ! err="$(jq empty "$f" 2>&1)"; then
        echo "  ❌ $f"
        printf '%s\n' "$err" | sed 's/^/      /'
        fail=$((fail + 1))
    fi
done < <(find "$PLUGIN_ROOT" \( -path '*/.git' -o -path '*/__pycache__' \) -prune -o -name '*.json' -type f -print)
if [ "$fail" -eq 0 ]; then
    echo "  ✅ 모든 .json 통과"
else
    errors=$((errors + fail))
fi

# ── 4. 종속어 검출 (워크스페이스/사용자/조직 종속 문자열) ─
echo "[4/4] 종속어 검출 (사용자 환경에 박힌 절대경로 등)"
viol=0

# 4-1. 사용자 홈 절대경로 노출 — 다른 사용자 환경에서 깨지는 fallback / 예시 path.
#      shellcheck source 주석은 정적 분석 hint 라 예외.
while IFS=: read -r f line text; do
    case "$text" in
        *shellcheck*source*) continue ;;
    esac
    rel="${f#$PLUGIN_ROOT/}"
    echo "  ❌ 사용자 홈 절대경로 — $rel:$line"
    echo "      ${text:0:160}"
    viol=$((viol + 1))
done < <(grep -rn '/home/[a-z][a-z0-9_-]*/' \
            --include='*.md' --include='*.sh' --include='*.py' --include='*.json' \
            "$PLUGIN_ROOT" 2>/dev/null \
        | grep -v '/.git/' || true)

if [ "$viol" -eq 0 ]; then
    echo "  ✅ 종속어 검출 없음"
else
    warnings=$((warnings + viol))
fi

echo
echo "── 결과 ──"
echo "  errors:   $errors"
echo "  warnings: $warnings"

if [ "$errors" -gt 0 ]; then
    echo "❌ 문법 오류가 있습니다 — 커밋 전 수정 필요."
    exit 1
fi
if [ "$warnings" -gt 0 ]; then
    echo "⚠ 종속어 경고 — 일반 사용자 환경에서 깨질 수 있습니다. 절대경로는 \$CLAUDE_PLUGIN_ROOT / placeholder 로 일반화 권장."
    exit 2
fi
echo "✅ 모든 검증 통과"
