#!/usr/bin/env bash
# /orch:mp-up <issue-id> [--force]
# orch가 호출. MP-XX 팀리더 pane을 띄운다.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

if [ "$#" -lt 1 ]; then
    cat >&2 <<EOF
사용법: /orch:mp-up <issue-id> [--force]
  issue-id 예: MP-13 / mp-13 / 13 (모두 mp-13으로 정규화)
  --force: 이미 떠 있는 leader가 있어도 cascade kill 후 재생성
EOF
    exit 2
fi

raw_id="$1"
shift || true
force=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --force) force=1 ;;
        *) echo "ERROR: 알 수 없는 옵션: $1" >&2; exit 2 ;;
    esac
    shift
done

mp_id="$(orch_normalize_issue_id "$raw_id" || true)"
if [ -z "$mp_id" ]; then
    echo "ERROR: issue-id '$raw_id' 정규화 실패. MP-NN 또는 NN 형식 사용." >&2
    exit 2
fi

orch_settings_require || exit 2

caller="$(orch_detect_self 2>/dev/null || true)"
if [ "$caller" != "orch" ]; then
    echo "ERROR: /orch:mp-up 은 orch에서만 호출 가능 (현재: ${caller:-unknown})" >&2
    echo "  orch pane이 등록 안 돼 있으면 먼저 /orch:up 실행" >&2
    exit 2
fi

if orch_worker_exists "$mp_id"; then
    if [ "$force" -eq 1 ]; then
        echo "INFO: 기존 $mp_id leader cascade kill"
        existing_pane="$(orch_worker_field "$mp_id" pane_id 2>/dev/null || true)"
        if [ -n "$existing_pane" ] && orch_pane_alive "$existing_pane"; then
            tmux kill-pane -t "$existing_pane" 2>/dev/null || true
        fi
        sub_window="$(tmux list-windows -t "$ORCH_TMUX_SESSION" -F '#{window_id} #W' 2>/dev/null \
            | awk -v n="$mp_id" '$2==n {print $1}' | head -n1)"
        if [ -n "$sub_window" ]; then
            tmux kill-window -t "$sub_window" 2>/dev/null || true
        fi
        rm -rf "$(orch_scope_dir "$mp_id")"
        orch_worker_unregister "$mp_id"
    else
        echo "ERROR: $mp_id 이미 등록됨. cascade 재생성하려면 --force" >&2
        exit 2
    fi
fi

# scope skeleton (runs/ wrapper 가 기본 위치)
mkdir -p "$ORCH_RUNS_DIR"
scope_dir="$(orch_scope_dir "$mp_id")"
mkdir -p "$scope_dir/inbox" "$scope_dir/archive" "$scope_dir/workers" "$scope_dir/worktrees"
mkdir -p "$ORCH_INBOX" "$ORCH_ARCHIVE" "$ORCH_WORKERS"

# leader pane (mp-NN 이름의 새 윈도우 — 이후 워커들도 이 윈도우에 합류)
ids="$(orch_new_window "$mp_id" "$scope_dir")"
read -r leader_window leader_pane <<<"$ids"
if [ -z "$leader_pane" ]; then
    echo "ERROR: leader pane 생성 실패" >&2
    exit 2
fi

orch_worker_register "$mp_id" "leader" "$leader_window" "$leader_pane" "$scope_dir"

tmux send-keys -t "$leader_pane" "export ORCH_WORKER_ID=$mp_id ORCH_BIN_DIR=$LIB_DIR && claude" Enter
sleep 4

projects_blob="$(orch_settings_projects | tr '\n' ' ')"
mp_upper="${mp_id^^}"

first_msg="너는 ${mp_id} 팀리더(leader)다.

[역할]
- 사용자가 orch에 위임한 이슈 ${mp_upper}을 책임지고 끝낸다.
- 자기 산하 프로젝트 워커를 spawn / 메시지 라우팅 / shutdown — 모두 leader가 관리.
- 산하 워커가 다른 프로젝트에 질문하면 leader가 받아 그 프로젝트 워커에게 전달.

[셋업]
1. mcp__linear-server__get_issue 로 ${mp_upper} 컨텍스트 가져오기 (description / acceptance criteria).
2. cat .orch/settings.json 으로 사용 가능 프로젝트 확인 (현재: ${projects_blob}).
3. 작업 계획 수립 후 어느 프로젝트(들)에서 작업할지 결정.

[프로젝트 선택 가이드]
- 1차: settings.json 의 description 의 \"책임\" 항목으로 매칭.
- 2차 (description 만으로 모호하면): 후보 프로젝트의 CLAUDE.md 를 직접 읽어 도메인 경계 확인.
    예: cat <projects.<alias>.path>/CLAUDE.md   (path 는 settings.json 에서 조회)
- 그래도 불확실하면 orch 에 질문해 사용자 결정 받기 — 잘못된 프로젝트에 spawn 하지 말 것.

[워커 spawn]
  /orch:leader-spawn <project-alias> [type]
  예: /orch:leader-spawn server fix
  → .orch/runs/${mp_id}/worktrees/<project> 에 git worktree 생성
  → ${mp_id} tmux 윈도우 안에서 워커 pane 시작
  → 워커는 ORCH_WORKER_ID=${mp_id}/<project> 로 식별됨

[메시지 라우팅 — Hub-and-Spoke]
- 산하 워커에게 지시: /orch:send ${mp_id}/<project> '<지시>'
- 산하 워커는 /orch:send ${mp_id} '<답>' 로 답신
- orch 보고 (사용자에 전달용): /orch:send orch '<요약>'
- 워커끼리 직접 통신 차단됨 — 항상 leader 경유
- 다른 MP의 leader/워커와 통신 차단됨 — 의존 있으면 orch에 escalate

[중요 — 메시지 본문에 따옴표·줄바꿈·백틱이 있으면 슬래시 명령 대신 Bash 도구 + heredoc]
  bash -c \"\$ORCH_BIN_DIR/send.sh <target> <<'ORCH_MSG'
  여러 줄 메시지
  '따옴표' 와 \\\`백틱\\\` 그대로 안전
  ORCH_MSG\"
  \$ORCH_BIN_DIR 는 leader/worker 시작 시 자동 export 됨. 'send.sh' 만 쓰면 PATH 못 찾아 'command not found' 로 실패하니 반드시 \$ORCH_BIN_DIR 접두 사용.
  슬래시 명령 /orch:send 는 \$ARGUMENTS 를 bash 명령줄에 그대로 넣기 때문에 특수문자에서 파서가 깨집니다.

[테스트 정책]
- 워커들에게는 자기 영역 단위·통합 테스트만 지시. 크로스-프로젝트 E2E 는 로컬 환경 한계로 SKIP — 발견된 케이스는 후속 이슈 메모로만 남기고 본 작업에 묶지 말 것.
- 워커 작업은 독립이라고 가정. 의존이 생기면 leader 가 작업을 분해해 순서를 정한다.

[컨텍스트 관리]
- 컨텍스트 사용량이 150k 토큰 넘으면 보고 직후 /compact 실행. 워커들에게도 같은 가이드 전달.

[PR 흐름 — 4단계 라이프사이클]

1. **CI 통과** — 워커는 PR 생성 후 \`gh pr checks <pr> --watch --required\` 로 필수 CI 통과까지 직접 대기.
   - 통과 → 워커가 leader 에 'PR #N ready for review + URL' 답신.
   - 실패 → 워커가 로그 발췌 동봉해 보고. 자기 영역이면 직접 수정 후 push, 모호하면 leader 라우팅 결정.

2. **코드 리뷰** — 'ready for review' 받으면 leader 가 곧바로:
     /orch:review-spawn <project> <pr-num>
   reviewer 가 깨끗한 컨텍스트로 PR 검토 후 코멘트 답신 + 자기 종료.
   reviewer 답신 형식: \`[review PR #N] LGTM\` 또는 \`[review PR #N] needs-changes\` + 코멘트.
   - **needs-changes** → reviewer 답신을 그대로 (또는 prefix 만 붙여) 작업 워커에 라우팅 → 워커 수정·push → 're-review please' 답신 → 다시 /orch:review-spawn 으로 새 reviewer (라운드 N).
   - **LGTM** → 답신을 그대로 작업 워커에 라우팅. 워커 안내문이 'LGTM 받으면 즉시 wait-merge.sh 진입' 으로 설계됐으니 별도 '머지 대기 시작' 지시 메시지 보낼 필요 없음.

3. **머지 대기** — 워커가 LGTM 메시지 수신 직후 자동으로:
     bash \$ORCH_BIN_DIR/wait-merge.sh <pr-num>
   를 30s 간격 블로킹 폴링. 사용자가 PR 머지하면 워커가 'PR #N merged' 답신 후 worker-shutdown.sh 로 자기 종료.
   - exit 1 (CLOSED 미머지) / exit 2 (timeout) → 워커가 leader 에 보고하고 대기 — leader 가 사용자에 escalate 또는 후속 결정.

   ⚠ leader 가 LGTM 라우팅 후 워커가 wait-merge 진입하지 않은 상태로 한참 멈춰 있으면 (워커가 잊었거나 라우팅 메시지에 LGTM 토큰이 없는 경우) leader 가 명시적 트리거:
       \"위 PR # <pr> LGTM 받았으니 \\\$ORCH_BIN_DIR/wait-merge.sh <pr> 실행\"
   메시지로 보강. 그러나 정상 경로에선 reviewer 답신 한 번 라우팅으로 끝나야 한다.

4. **모든 산하 워커 종료 확인 후 mp-down**:
     /orch:mp-down ${mp_id}
   산하 reviewer + 작업 워커 cascade kill, 머지된 worktree 자동 정리, ${mp_id} 윈도우 통째 사라짐 (leader 자기까지 자동 종료). 사용자가 수동으로 닫지 않음.
   orch 에 종료 보고 + REPORT.html 자동 작성 요청 메시지 발송.

[중요 — 임의 종결 금지]
- 워커 보고 없이 'PR 만들었으니 사용자가 머지' 라고 종결 짓지 말 것 (mp-9 사례 — checkstyle 사일런트 실패).
- 리뷰 없이 머지 대기로 점프하지 말 것 — 깨끗한 컨텍스트 리뷰가 v2.1 의 안전망.

지금 1~3 단계 진행하고 작업 계획을 /orch:send orch 로 보고하세요."

tmux send-keys -t "$leader_pane" "$first_msg"
sleep 0.3
tmux send-keys -t "$leader_pane" Enter

echo "OK leader=$mp_id pane=$leader_pane window=$leader_window"
echo "  scope_dir: $scope_dir"

# Slack 알림 — leader 가 막 떴고 plan 메시지를 곧 orch 로 송신할 예정.
"${LIB_DIR}/notify-slack.sh" mp_select "$mp_id" "leader 떴음 — 곧 plan 컨펌 메시지 도착" || true
