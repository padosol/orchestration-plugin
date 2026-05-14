#!/usr/bin/env bash
# orch_route_check — 트래커별 다양한 키 형식에서도 라우팅 정책이 정상 동작.

set -euo pipefail

cd "$SANDBOX"
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/core/lib.sh"

ok() {
    if ! orch_route_check "$1" "$2" 2>/dev/null; then
        echo "FAIL allow expected: $1 → $2" >&2
        exit 1
    fi
}
deny() {
    if orch_route_check "$1" "$2" 2>/dev/null; then
        echo "FAIL deny expected: $1 → $2" >&2
        exit 1
    fi
}

# 허용 흐름
ok   "orch"           "MP-13"
ok   "MP-13"          "orch"
ok   "MP-13"          "MP-13/server"
ok   "MP-13/server"   "MP-13"
ok   "PROJ-456"       "PROJ-456/ui"
ok   "142"            "142/api"

# 차단
deny "MP-13/server"   "MP-13/ui"        # 워커끼리 직접
deny "MP-13/server"   "orch"            # 워커 → orch
deny "orch"           "MP-13/server"    # orch → 워커
deny "MP-13"          "PROJ-456"        # cross-issue leader 끼리
deny "MP-13"          "PROJ-456/server" # cross-issue
deny "MP-13/server"   "PROJ-456"        # cross-issue
deny "MP-13"          "MP-13"           # self

echo "OK route-check-cross-issue"
