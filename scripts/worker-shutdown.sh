#!/usr/bin/env bash
# worker-shutdown.sh — 워커가 작업 완료 후 자기 pane 을 정리한다.
#
# 호출 시점:
#   - wait-merge.sh 가 MERGED 감지 → leader 에 'merged' 답신 → 이 스크립트
#   - reviewer 가 코멘트 답신 후 → 이 스크립트 (단발성 reviewer 자동 종료)
#
# 동작:
#   1. self worker_id 추론 (kind=worker 만 허용 — leader/orch 는 거부)
#   2. workers/<role>.json 등록 해제
#   3. tmux kill-pane $TMUX_PANE → pane child(Claude 포함) 모두 SIGHUP 종료
#
# Claude Code 가 떠 있어 'exit' 명령이 셸에 닿지 않는 문제를 우회한다.
# 마지막 명령이 자기 pane 을 죽이므로 호출자(Claude)는 결과를 받지 못한다.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

self="$(orch_detect_self 2>/dev/null || true)"
if [ -z "$self" ]; then
    echo "ERROR: worker_id 추론 실패. tmux pane 안에서 실행해야 합니다." >&2
    exit 2
fi

kind="$(orch_wid_kind "$self")"
case "$kind" in
    worker)
        ;;
    *)
        echo "ERROR: worker-shutdown 은 worker(mp-NN/<project>) 만 호출 가능. 현재 self=$self (kind=$kind)" >&2
        echo "  - leader 종료는 /orch:mp-down 으로." >&2
        echo "  - orch 종료는 /orch:down 으로." >&2
        exit 2
        ;;
esac

pane_id="${TMUX_PANE:-}"
if [ -z "$pane_id" ]; then
    echo "ERROR: TMUX_PANE 미설정 — tmux 안에서 호출하세요." >&2
    exit 2
fi

echo "[shutdown] worker_id=$self pane=$pane_id self-terminating" >&2

# registry 보존 — <scope>/workers-archive/<role>.json 으로 mv + terminated_at 추가.
# report.sh 가 종료된 워커의 sidecar(토큰·도구 jsonl) 를 분석할 수 있도록 cwd/started_at
# 필드 유지가 필요. 실패해도 진행 — pane kill 이 본질.
orch_worker_archive_local "$self" || true

# reviewer 워커가 종료할 때는 PR 리뷰 코멘트를 막 게시한 직후라 머지 가능 상태.
# 작업 워커 종료(머지 완료 후)는 mp-down 의 mp_done 알림이 대신 처리하므로 여기선 noop.
role="$(orch_wid_role "$self" 2>/dev/null || true)"
if [ "${role#review-}" != "$role" ]; then
    scope="$(orch_wid_scope "$self" 2>/dev/null || true)"
    "${LIB_DIR}/notify-slack.sh" pr_ready "$scope" "${self}: 리뷰 코멘트 게시 완료, 머지 가능" || true
fi

# 마지막 명령: 자기 pane kill. 이 명령 이후로는 stdout/stderr 모두 사라진다.
exec tmux kill-pane -t "$pane_id"
