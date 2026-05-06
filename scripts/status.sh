#!/usr/bin/env bash
# /orch:status — 위계 출력 (orch + leader + 각 leader 산하 워커).

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

if tmux has-session -t "$ORCH_TMUX_SESSION" 2>/dev/null; then
    tmux_status="UP"
else
    tmux_status="DOWN"
fi

printf 'tmux session: %s (%s)\n' "$ORCH_TMUX_SESSION" "$tmux_status"

if orch_settings_exists; then
    proj_count="$(orch_settings_projects | wc -l)"
    printf 'settings.json: %s (%d projects)\n\n' "$ORCH_SETTINGS" "$proj_count"
else
    printf 'settings.json: (없음 — /orch:setup 필요)\n\n'
fi

print_row() {
    local wid="$1" indent="$2"
    local cnt mt pane alive
    cnt="$(orch_inbox_count "$wid")"
    mt="$(orch_inbox_mtime "$wid")"
    pane="$(orch_worker_field "$wid" pane_id 2>/dev/null || true)"
    if [ -n "$pane" ] && orch_pane_alive "$pane"; then
        alive="alive"
    elif [ -n "$pane" ]; then
        alive="DEAD"
    else
        alive="(unregistered)"
    fi
    printf '%s%-32s %-12s pending=%-3s last=%s\n' "$indent" "$wid" "[$alive]" "$cnt" "$mt"
}

# orch
print_row "orch" ""

# leaders + 산하 워커
mapfile -t leaders < <(orch_active_leaders)
if [ "${#leaders[@]}" -eq 0 ]; then
    printf '\n(active leader 없음 — /orch:mp-up MP-XX 로 시작)\n'
else
    printf '\n'
    for leader in "${leaders[@]}"; do
        print_row "$leader" ""
        mapfile -t subs < <(orch_active_sub_workers "$leader")
        for sub in "${subs[@]}"; do
            print_row "$sub" "  └─ "
        done
    done
fi

# orphan 검출: <scope>/workers/ 에 leader가 없는 산하 워커
echo
orphans=()
for d in "$ORCH_ROOT"/mp-*/; do
    [ -d "$d" ] || continue
    scope="$(basename "$d")"
    if ! orch_worker_exists "$scope"; then
        # 이 scope에 leader 없음. 산하 워커가 있다면 orphan
        for sw in "${d}workers"/*.json; do
            [ -f "$sw" ] || continue
            orphans+=("${scope}/$(basename "$sw" .json)")
        done
    fi
done
if [ "${#orphans[@]}" -gt 0 ]; then
    printf 'WARN orphan workers (leader 없음): %s\n' "${orphans[*]}"
fi
