#!/usr/bin/env bash
# /orch:status — 위계 출력 (orch + leader + 각 leader 산하 워커).
# Top-line aggregate + 인박스 안 [direction-check] 잔존 배지.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

# 인박스 파일에 [direction-check] 라벨이 미처리로 남아있으면 0(true).
# /orch:check-inbox 가 메시지를 archive 로 옮기므로 inbox 잔존 == 미처리 의미.
orch_inbox_has_direction_check() {
    local wid="$1" path
    path="$(orch_inbox_path "$wid" 2>/dev/null)" || return 1
    [ -s "$path" ] || return 1
    grep -qF '[direction-check]' "$path" 2>/dev/null
}

if tmux has-session -t "$ORCH_TMUX_SESSION" 2>/dev/null; then
    tmux_status="UP"
else
    tmux_status="DOWN"
fi

printf 'tmux session: %s (%s)\n' "$ORCH_TMUX_SESSION" "$tmux_status"

if orch_settings_exists; then
    proj_count="$(orch_settings_projects | wc -l)"
    printf 'settings.json: %s (%d projects)\n' "$ORCH_SETTINGS" "$proj_count"
else
    printf 'settings.json: (없음 — /orch:setup 필요)\n'
fi

mapfile -t leaders < <(orch_active_leaders)

# pass 1: aggregate. inbox 카운트와 direction-check 검출은 각 row 출력 시 한 번 더 호출되지만
# 파일 stat + 작은 grep 이라 비용 미미. 명확성 우선.
agg_leaders=0
agg_workers=0
agg_dead=0
agg_pending=0
agg_dchecks=0

aggregate_one() {
    local wid="$1" cnt pane
    cnt="$(orch_inbox_count "$wid")"
    agg_pending=$((agg_pending + cnt))
    pane="$(orch_worker_field "$wid" pane_id 2>/dev/null || true)"
    if [ -n "$pane" ] && ! orch_pane_alive "$pane"; then
        agg_dead=$((agg_dead + 1))
    fi
    if orch_inbox_has_direction_check "$wid"; then
        agg_dchecks=$((agg_dchecks + 1))
    fi
}

# orch 자체 인박스 (leader → orch 보고 누적)
orch_pending_cnt="$(orch_inbox_count "orch")"
agg_pending=$((agg_pending + orch_pending_cnt))
if orch_inbox_has_direction_check "orch"; then
    agg_dchecks=$((agg_dchecks + 1))
fi

for leader in "${leaders[@]}"; do
    agg_leaders=$((agg_leaders + 1))
    aggregate_one "$leader"
    mapfile -t subs < <(orch_active_sub_workers "$leader")
    for sub in "${subs[@]}"; do
        agg_workers=$((agg_workers + 1))
        aggregate_one "$sub"
    done
done

# aggregate 한 줄 — leader 있을 때만 의미있음
if [ "$agg_leaders" -gt 0 ]; then
    summary="active: $agg_leaders leaders · $agg_workers workers"
    [ "$agg_dead" -gt 0 ] && summary="$summary ($agg_dead dead)"
    summary="$summary · pending msgs $agg_pending · direction-check $agg_dchecks"
    [ "$agg_dchecks" -gt 0 ] && summary="$summary  ⚠"
    printf '%s\n\n' "$summary"
else
    printf '\n'
fi

print_row() {
    local wid="$1" indent="$2"
    local cnt mt pane alive dcheck
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
    dcheck=""
    orch_inbox_has_direction_check "$wid" && dcheck="  [direction-check]"
    printf '%s%-32s %-12s pending=%-3s last=%s%s\n' "$indent" "$wid" "[$alive]" "$cnt" "$mt" "$dcheck"
}

# pass 2: row 출력
print_row "orch" ""

if [ "${#leaders[@]}" -eq 0 ]; then
    printf '\n(active leader 없음 — /orch:issue-up MP-XX 로 시작)\n'
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
# runs/<scope>/ 와 평탄 <scope>/ 양쪽 스캔. .orch root 의 reserved 디렉토리 제외.
echo
orphans=()
shopt -s nullglob
declare -a candidates=()
for d in "$ORCH_RUNS_DIR"/*/; do
    [ -d "$d" ] && candidates+=("$d")
done
for d in "$ORCH_ROOT"/*/; do
    [ -d "$d" ] || continue
    case "$(basename "${d%/}")" in
        inbox|archive|workers|runs) continue ;;
    esac
    candidates+=("$d")
done
for d in "${candidates[@]}"; do
    scope="$(basename "${d%/}")"
    orch_id_safe "$scope" || continue
    [ "$scope" = "orch" ] && continue
    if ! orch_worker_exists "$scope"; then
        # 이 scope에 leader 없음. 산하 워커가 있다면 orphan
        for sw in "${d}workers"/*.json; do
            [ -f "$sw" ] || continue
            orphans+=("${scope}/$(basename "$sw" .json)")
        done
    fi
done
shopt -u nullglob
if [ "${#orphans[@]}" -gt 0 ]; then
    printf 'WARN orphan workers (leader 없음): %s\n' "${orphans[*]}"
fi
