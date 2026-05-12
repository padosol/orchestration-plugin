#!/usr/bin/env bash
# Regression guard: github + 자유 식별자 (예: feature-x, feature-2026) 조합은
# scope dir 생성 / tmux pane spawn / registry 등록 같은 side effect **이전** 에
# 차단되어야 한다. 그래야 실패 시 .orch/runs/<id>/, workers/<id>.json, tmux 잔재가 남지 않는다.
#
# 또한 'feature-2026' 같은 자유 id 의 부분 숫자가 GitHub issue #2026 으로 오인되지 않도록
# 전체 숫자 (^[0-9]+$) 매칭으로 검증해야 한다.

set -euo pipefail

src_up="$PLUGIN_ROOT/scripts/issue-up.sh"
[ -f "$src_up" ] || { echo "FAIL: $src_up 없음" >&2; exit 1; }

# 1. 검증 시점이 side effects 보다 앞이어야 — 'orch_settings_require' 이후, 그러나
#    'orch_worker_exists', 'orch_new_window', 'orch_worker_register' 보다는 먼저.
awk_out="$(awk '
    /effective_tracker = "github"/ { ev = NR }
    /^if \[ "\$effective_tracker" = "github" \]; then/ { gh_check = NR }
    /orch_worker_exists "\$mp_id"/ { worker_exists = NR }
    /orch_new_window "\$mp_id"/ { new_window = NR }
    /orch_worker_register "\$mp_id" "leader"/ { worker_register = NR }
    END {
        printf "gh_check=%d worker_exists=%d new_window=%d worker_register=%d\n",
            gh_check, worker_exists, new_window, worker_register
    }
' "$src_up")"

# 위 4 좌표를 본다
eval "$awk_out"

if [ "${gh_check:-0}" -eq 0 ]; then
    echo "FAIL: issue-up.sh 에 'if [ \"\$effective_tracker\" = \"github\" ]' 검증 분기 없음" >&2
    exit 1
fi
if [ "${gh_check}" -gt "${worker_exists:-0}" ] || [ "${gh_check}" -gt "${new_window:-0}" ] || [ "${gh_check}" -gt "${worker_register:-0}" ]; then
    echo "FAIL: github 검증이 side effects (worker_exists=${worker_exists} / new_window=${new_window} / worker_register=${worker_register}) 보다 늦음 (gh_check=${gh_check})" >&2
    exit 1
fi

# 2. 검증식이 부분 매칭이 아닌 전체 매칭 (^[0-9]+$) 이어야 — feature-2026 → 2026 오인 차단
if ! grep -qE '\[\[ ! "\$mp_id" =~ \^\[0-9\]\+\$ \]\]' "$src_up"; then
    echo "FAIL: github 검증이 전체 숫자 매칭 (^[0-9]+\$) 정규식이 아님" >&2
    exit 1
fi

# 3. 동적 시뮬레이션: 같은 정규식이 'feature-2026' 을 reject 하고 '2026' 을 accept 하는지
out="$(
    set -euo pipefail
    classify() {
        local mp_id="$1"
        if [[ ! "$mp_id" =~ ^[0-9]+$ ]]; then
            printf 'block(%s) ' "$mp_id"
        else
            printf 'pass(%s) ' "$mp_id"
        fi
    }
    classify "feature-2026"
    classify "feature-x"
    classify "MP-13"
    classify "2026"
    classify "0"
)"
case "$out" in
    "block(feature-2026) block(feature-x) block(MP-13) pass(2026) pass(0) ") : ;;
    *) echo "FAIL: 전체 숫자 검증 시뮬레이션 결과 불일치 — got: '$out'" >&2; exit 1 ;;
esac

# 4. --no-issue 가 검증을 우회해야 — 'effective_tracker' 가 'none' 으로 바뀌어
#    github 분기 자체를 안 타도록 위에 명시. 코드 흐름 확인.
if ! grep -q 'effective_tracker="none"' "$src_up"; then
    echo "FAIL: --no-issue 가 effective_tracker=none 으로 우회하는 분기 없음" >&2
    exit 1
fi

# 5. 에러 메시지에 --no-issue / 다른 트래커 우회 안내가 있어야
if ! grep -q -- '--no-issue' "$src_up"; then
    echo "FAIL: github 검증 에러 메시지에 '--no-issue' 우회 안내 없음" >&2
    exit 1
fi

echo "OK github-free-id-blocked-early"
