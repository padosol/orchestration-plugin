#!/usr/bin/env bash
# /orch:issue-down <issue-id> [--no-cleanup] — leader cascade shutdown.
# orch가 호출 → leader pane에 /orch:issue-down 자동 전달 (leader가 cleanup).
# leader가 호출 → 산하 워커 cascade kill + 머지 브랜치 worktree 자동 정리 + scope dir archive.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="$ORCH_SCRIPTS_ROOT"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/core/lib.sh
source "${ORCH_SCRIPTS_ROOT}/core/lib.sh"
orch_install_error_trap "$0"

if [ "$#" -lt 1 ]; then
    echo "사용법: /orch:issue-down <issue-id> [--no-cleanup]" >&2
    exit 2
fi

raw_id="$1"
shift || true

do_cleanup=1
do_report=1
while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-cleanup) do_cleanup=0 ;;
        --no-report)  do_report=0 ;;
        *) echo "ERROR: 알 수 없는 옵션: $1" >&2; exit 2 ;;
    esac
    shift
done

mp_id="$(orch_normalize_issue_id "$raw_id" || true)"
if [ -z "$mp_id" ]; then
    echo "ERROR: issue-id '$raw_id' 정규화 실패" >&2
    exit 2
fi

self="$(orch_detect_self 2>/dev/null || true)"
self_kind="$(orch_wid_kind "${self:-}")"

run_cleanup_if_enabled() {
    if [ "$do_cleanup" -eq 1 ]; then
        echo "INFO: 머지된 브랜치 worktree 자동 정리"
        orch_cleanup_merged_worktrees "$mp_id"
    else
        echo "INFO: --no-cleanup 지정 — worktree 정리 SKIP"
    fi
}

run_report_if_enabled() {
    # archive 전에 호출. scope_dir 안에 REPORT-data.md 저장 → archive 가 함께 옮김.
    if [ "$do_report" -eq 0 ]; then
        echo "INFO: --no-report 지정 — 데이터 덤프 SKIP"
        return 0
    fi
    local target="$1"  # scope_dir 경로
    [ -d "$target" ] || return 0
    if "${LIB_DIR}/report.sh" "$mp_id" > "$target/REPORT-data.md" 2>/dev/null; then
        echo "INFO: 데이터 덤프 → $target/REPORT-data.md"
    else
        echo "WARN: report.sh 실패 — REPORT-data.md 생성 못함"
    fi
}

# orch가 호출한 경우
if [ "$self" = "orch" ]; then
    if ! orch_worker_exists "$mp_id"; then
        echo "INFO: $mp_id leader 등록 없음 — 잔재만 정리"
        run_cleanup_if_enabled
        # leader cascade 가 archive mv 만 하고 죽은 경우 git 메타·로컬 브랜치 잔재가 남는다.
        # 모든 project 에 worktree prune 1회 + mp_id 패턴 머지 브랜치 후보 출력.
        if [ "$do_cleanup" -eq 1 ]; then
            orch_orphan_cleanup_suggest "$mp_id"
        fi
        scope_dir_path="$(orch_scope_dir "$mp_id" 2>/dev/null || true)"
        if [ -n "$scope_dir_path" ] && [ -d "$scope_dir_path" ]; then
            run_report_if_enabled "$scope_dir_path"
            archive_dir="${ORCH_ARCHIVE}/${mp_id}-$(date +%Y-%m-%d)"
            [ -d "$archive_dir" ] && archive_dir="${archive_dir}-$(date +%H%M%S)"
            mkdir -p "$ORCH_ARCHIVE"
            mv "$scope_dir_path" "$archive_dir"
            echo "  archived $archive_dir"
        fi
        leftover_window="$(tmux list-windows -t "$ORCH_TMUX_SESSION" -F '#{window_id} #W' 2>/dev/null \
            | awk -v n="$mp_id" '$2==n {print $1}' | head -n1)"
        if [ -n "$leftover_window" ]; then
            tmux kill-window -t "$leftover_window" 2>/dev/null || true
            echo "  killed leftover window $leftover_window"
        fi
        echo "OK orch-cleanup mp_id=$mp_id"
        exit 0
    fi
    leader_pane="$(orch_worker_field "$mp_id" pane_id 2>/dev/null || true)"
    if [ -n "$leader_pane" ] && orch_pane_alive "$leader_pane"; then
        echo "INFO: leader pane=$leader_pane 에 cascade shutdown 위임"
        delegated_cmd="/orch:issue-down $mp_id"
        [ "$do_cleanup" -eq 0 ] && delegated_cmd="$delegated_cmd --no-cleanup"
        [ "$do_report" -eq 0 ] && delegated_cmd="$delegated_cmd --no-report"
        orch_send_keys_line "$leader_pane" "$delegated_cmd" \
            || echo "WARN: leader $mp_id (pane=$leader_pane) 에 위임 명령 전달 실패" >&2
        echo "OK delegated to leader $mp_id"
        exit 0
    fi
    # leader pane 죽음 — orch 가 직접 정리
    echo "INFO: leader $mp_id pane 이미 죽음 — 직접 정리"
    run_cleanup_if_enabled
    # leader 가 비정상 종료한 경우 잔재 prune + 머지된 브랜치 후보 출력.
    if [ "$do_cleanup" -eq 1 ]; then
        orch_orphan_cleanup_suggest "$mp_id"
    fi
    scope_dir_path="$(orch_scope_dir "$mp_id")"
    [ -d "$scope_dir_path" ] && run_report_if_enabled "$scope_dir_path"
    archive_dir="${ORCH_ARCHIVE}/${mp_id}-$(date +%Y-%m-%d)"
    [ -d "$archive_dir" ] && archive_dir="${archive_dir}-$(date +%H%M%S)"
    mkdir -p "$ORCH_ARCHIVE"
    [ -d "$scope_dir_path" ] && mv "$scope_dir_path" "$archive_dir"
    orch_worker_unregister "$mp_id"
    orch_inbox_cleanup "$mp_id"
    echo "OK archived $archive_dir"
    # Slack 알림 — leader pane 이미 죽어서 orch 가 직접 정리한 경로.
    "${LIB_DIR}/notify/notify-slack.sh" mp_done "$mp_id" "leader 이미 종료, 정리 완료" "$archive_dir" || true
    exit 0
fi

# leader 본인이 호출
if [ "$self_kind" != "leader" ] || [ "$self" != "$mp_id" ]; then
    echo "ERROR: /orch:issue-down 은 orch 또는 해당 leader($mp_id) 에서만 호출 가능 (현재: ${self:-unknown})" >&2
    exit 2
fi

echo "INFO: $mp_id 산하 워커 cascade kill"
for sub_wid in $(orch_active_sub_workers "$mp_id"); do
    sub_pane="$(orch_worker_field "$sub_wid" pane_id 2>/dev/null || true)"
    if [ -n "$sub_pane" ] && orch_pane_alive "$sub_pane"; then
        tmux kill-pane -t "$sub_pane" 2>/dev/null || true
        echo "  killed $sub_wid (pane=$sub_pane)"
    fi
done

# worktree cleanup — pane kill 직후, 윈도우/scope archive 직전.
# git worktree remove 는 worktree 경로가 그대로 있어야 작동하므로 archive 전에.
run_cleanup_if_enabled

# 데이터 덤프 — archive 전에 scope_dir 안에 저장.
scope_dir_path="$(orch_scope_dir "$mp_id")"
[ -d "$scope_dir_path" ] && run_report_if_enabled "$scope_dir_path"

# issue_id 윈도우 식별 — leader 자기 자신이 그 윈도우에 있으므로 kill 은 마지막에.
mp_window="$(tmux list-windows -t "$ORCH_TMUX_SESSION" -F '#{window_id} #W' 2>/dev/null \
    | awk -v n="$mp_id" '$2==n {print $1}' | head -n1)"

# scope dir archive
archive_dir="${ORCH_ARCHIVE}/${mp_id}-$(date +%Y-%m-%d)"
[ -d "$archive_dir" ] && archive_dir="${archive_dir}-$(date +%H%M%S)"
mkdir -p "$ORCH_ARCHIVE"
if [ -d "$scope_dir_path" ]; then
    mv "$scope_dir_path" "$archive_dir"
    echo "  archived to $archive_dir"
fi

orch_worker_unregister "$mp_id"
orch_inbox_cleanup "$mp_id"

# REPORT.html 생성 안내 — leader 가 cascade shutdown 직전 /orch:report 로 직접 생성하는 게
# 정상 흐름. 보통 archive_dir 에 이미 REPORT.html 존재. 누락 시 orch 자동 호출 X, 사용자 수동 복구.
report_hint=""
if [ "$do_report" -eq 1 ] && [ -f "$archive_dir/REPORT.html" ]; then
    report_hint=" REPORT.html: $archive_dir/REPORT.html"
elif [ "$do_report" -eq 1 ] && [ -f "$archive_dir/REPORT-data.md" ]; then
    report_hint=" ⚠ REPORT.html 누락 — leader 가 cascade shutdown 직전 /orch:report 호출을 건너뜀. 사용자가 \`/orch:report $mp_id\` 로 archive 의 REPORT-data.md 를 받아 수동 복구 가능 (orch 자동 호출 X)."
fi

# cleanup 요약 — leader pane stdout 이 곧 사라져 운영자가 결과를 볼 수 없으므로 inbox 알림에 포함.
cleanup_summary=""
if [ "$do_cleanup" -eq 1 ]; then
    cleanup_summary=" cleanup: cleaned=${ORCH_CLEANUP_SUMMARY_CLEANED:-0} kept=${ORCH_CLEANUP_SUMMARY_KEPT:-0} partial=${ORCH_CLEANUP_SUMMARY_PARTIAL:-0} skipped=${ORCH_CLEANUP_SUMMARY_SKIPPED:-0}."
fi

# orch에 종료 보고 (leader pane 이 곧 죽으므로 stdout 은 남지 않음 — 보고는 inbox 통해 전달)
orch_append_message "$mp_id" "orch" "[issue-down] $mp_id cascade shutdown 완료. archive: $archive_dir.${cleanup_summary} 머지 worktree 자동 정리(+pull), 미머지는 보존.$report_hint" >/dev/null
orch_notify "orch" || true

# Slack 알림 — MP 완료. archive 경로 + REPORT 작성 안내.
"${LIB_DIR}/notify/notify-slack.sh" mp_done "$mp_id" "cascade shutdown 완료. /orch:report 로 REPORT.html 작성 권유" "$archive_dir" || true

# 마지막: issue_id 윈도우(leader 자기 pane 포함) 통째로 kill — self-shutdown.
# 동기 kill 이 자기 pane 을 즉시 죽이면 이 스크립트 종료 후 잔여 명령이 없어 안전.
if [ -n "$mp_window" ]; then
    tmux kill-window -t "$mp_window" 2>/dev/null || true
fi
