#!/usr/bin/env bash
# /orch:issue-up <issue-id> [--force]
# orch가 호출. 사용자가 넘긴 <issue-id> 로 팀리더 pane을 띄운다 — 트래커별 키 형식 그대로
# (Linear MP-13, Jira PROJ-456, GitHub 142, 자유 issue42 등).

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

if [ "$#" -lt 1 ]; then
    cat >&2 <<EOF
사용법: /orch:issue-up <issue-id> [--force] [--no-issue]
  issue-id: 트래커의 키 그대로 ([A-Za-z0-9_-]+, 대소문자 보존).
            예: MP-13 (Linear) / PROJ-456 (Jira) / 142 (GitHub) / issue42 (자유)
  --force: 이미 떠 있는 leader가 있어도 cascade kill 후 재생성
  --no-issue: 트래커 설정 무시 (이번 한 번만). leader 가 orch 에 spec 직접 요청.
              사용 케이스: 이슈 만들기 번거로운 작은 작업 / 이슈 없이 try-out
EOF
    exit 2
fi

raw_id="$1"
shift || true
force=0
no_issue=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --force) force=1 ;;
        --no-issue) no_issue=1 ;;
        *) echo "ERROR: 알 수 없는 옵션: $1" >&2; exit 2 ;;
    esac
    shift
done

issue_id="$(orch_normalize_issue_id "$raw_id" || true)"
if [ -z "$issue_id" ]; then
    echo "ERROR: issue-id '$raw_id' 정규화 실패. [A-Za-z0-9_-]+ 만 허용 ('orch' 는 reserved)." >&2
    exit 2
fi
# 코드 호환을 위해 옛 변수명 mp_id 유지 (값은 issue_id 와 동일).
mp_id="$issue_id"

orch_settings_require || exit 2

caller="$(orch_detect_self 2>/dev/null || true)"
if [ "$caller" != "orch" ]; then
    echo "ERROR: /orch:issue-up 은 orch에서만 호출 가능 (현재: ${caller:-unknown})" >&2
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

# leader pane (issue_id 이름의 새 윈도우 — 이후 워커들도 이 윈도우에 합류)
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
# 표시·트래커 호출용 키 가공:
#   issue_display = 사용자 입력 그대로 (예: MP-13, PROJ-456, 142, issue42)
#   issue_num     = 트래커 fetch 에 넘기는 숫자 부분 — GitHub 처럼 숫자만 받는 호스트용.
#                   첫 [0-9]+ 시퀀스 추출. 숫자 없으면 빈 문자열.
issue_display="$mp_id"
issue_num="$(printf '%s' "$mp_id" | grep -Eo '[0-9]+' | head -1)"
tracker="$(orch_settings_issue_tracker)"
gh_repo="$(orch_settings_github_issue_repo 2>/dev/null || true)"
plugin_root="$(dirname "$LIB_DIR")"
workflows_dir="${plugin_root}/references/workflows"

# --no-issue 가 켜지면 워크스페이스 트래커 설정과 무관하게 spec 요청 모드.
effective_tracker="$tracker"
if [ "$no_issue" -eq 1 ]; then
    effective_tracker="none"
fi

case "$effective_tracker" in
    linear)
        issue_fetch_step="1. mcp__linear-server__get_issue ${issue_display} (description / acceptance criteria)"
        ;;
    github)
        if [ -n "$gh_repo" ]; then
            issue_fetch_step="1. \`gh issue view ${issue_num} --repo ${gh_repo} --json title,body,labels,milestone\` (description / acceptance criteria)"
        else
            issue_fetch_step="1. \`gh issue view ${issue_num} --json title,body,labels,milestone\` (현재 cwd 의 repo 기준 — settings.json 의 github_issue_repo 미설정이라 해당 repo 인지 확인 필요)"
        fi
        ;;
    gitlab)
        # GitLab Issues 자동 fetch — glab CLI 경유. issue_num 이 있으면 그 번호로,
        # 없으면 issue_display 그대로 (glab 가 reference 형식도 받음).
        if [ -n "$gh_repo" ]; then
            # github_issue_repo 가 gitlab 환경에서는 group/project 로 재해석됨
            issue_fetch_step="1. \`glab issue view ${issue_num:-$issue_display} --repo ${gh_repo} --output json\` (description / labels / milestone). glab 미설치/미인증 시 \`bash \$ORCH_BIN_DIR/send.sh orch <<'ORCH_MSG'\\n${issue_display} spec 부탁 — GitLab 이슈 본문/AC 붙여줘.\\nORCH_MSG\` 로 fallback."
        else
            issue_fetch_step="1. \`glab issue view ${issue_num:-$issue_display} --output json\` (현재 cwd 의 project 기준 — settings.json 의 github_issue_repo 미설정이라 해당 project 인지 확인 필요). glab 미설치/미인증 시 send.sh orch 로 spec 요청 fallback."
        fi
        ;;
    jira)
        # Jira 자동 fetch — jira-cli (ankitpokhrel/jira-cli) 경유. 사이트 URL/토큰은
        # ~/.config/.jira/.config.yml 에 사전 등록되어 있어야 함.
        issue_fetch_step="1. \`jira issue view ${issue_display} --plain\` (description / acceptance criteria). jira-cli 미설치/미인증 시 \`bash \$ORCH_BIN_DIR/send.sh orch <<'ORCH_MSG'\\n${issue_display} spec 부탁 — Jira 이슈 본문/AC 붙여줘.\\nORCH_MSG\` 로 fallback."
        ;;
    none|*)
        if [ "$no_issue" -eq 1 ] && [ "$tracker" != "none" ]; then
            tracker_note="(이번 호출만 --no-issue — 워크스페이스 트래커 설정 ${tracker} 는 다음 호출부터 그대로 적용)"
        else
            tracker_note="(트래커 미사용 모드)"
        fi
        issue_fetch_step="1. 이슈 컨텍스트 없음 ${tracker_note}. 본인 inbox 의 spec 메시지 또는 orch 의 첫 지시 확인. spec 부재 시 \`bash \$ORCH_BIN_DIR/send.sh orch <<'ORCH_MSG'\\n${issue_display} spec 부탁 — 작업 범위·acceptance·관련 repo 알려달라.\\nORCH_MSG\` 로 요청."
        ;;
esac

first_msg="너는 ${mp_id} 팀리더(leader)다. 10년차 시니어 엔지니어링 매니저로서 사용자가 위임한 ${issue_display} 을 책임지고 끝낸다 — spec 분해 / 산하 워커 spawn / 라우팅 / 통합 / shutdown. 의사결정은 코드·데이터 기반으로 하고, spec 이 모호하면 추측 진행 금지 — 사유 명시해 orch 에 escalate.

[셋업]
${issue_fetch_step}
2. cat .orch/settings.json — 사용 가능 프로젝트: ${projects_blob}
3. 어느 프로젝트(들)에서 작업할지 결정. 모호하면 후보 \`<path>/CLAUDE.md\` 확인. 그래도 불확실하면 orch 에 질문 — 잘못된 프로젝트에 spawn 금지.

[작업 타입 판별 — Phase Plan 직전 필수]
spec 의 title / labels / issuetype 에서 작업 타입 1회 추론. 타입에 따라 phase 구조와 reviewer 체크리스트가 달라지므로 phase plan 작성 전에 결정한다.

- **feature** — label 'feature' / 'feat' / 'enhancement' / 'new' 또는 title 'feat:' / 'feature:' 또는 (Jira) issuetype Story / New Feature
- **bug** — label 'bug' / 'defect' / 'regression' 또는 title 'fix:' / 'bug:' 또는 (Jira) issuetype Bug
- **refactor** — label 'refactor' / 'refac' / 'cleanup' / 'tech-debt' 또는 title 'refactor:' / 'refac:'

추론 실패 (라벨·prefix 모호) 시 **AskUserQuestion** 으로 한 번만 묻기 (3택: feature / bug / refactor). 추측 진행 금지.

결정 직후:
1. 타입에 해당하는 가이드 1회 Read — phase 템플릿 + Review 체크리스트를 phase plan 의 골격으로 사용:
   - feature: ${workflows_dir}/feature.md
   - bug:     ${workflows_dir}/bug.md
   - refactor: ${workflows_dir}/refactor.md
2. \`.orch/runs/${mp_id}/type\` 에 결정한 타입을 **소문자 한 단어** (feature|bug|refactor) 로 한 줄 기록 — review-spawn 이 읽어 reviewer 도 같은 가이드 적용:
   \`\`\`
   bash -c 'echo feature > .orch/runs/${mp_id}/type'
   \`\`\`

[Phase Plan — 필수, 사용자 GO 전 워커 spawn 금지]
모든 MP 는 phase 단위 순차 실행. 비-blocking 동시 spawn 으로 순서가 꼬이는 사고를 막기 위함. 단순 MP 라도 단일 phase 로 표현해 일관성 확보.

순서:
1. spec (issue 본문 또는 orch 첨부 spec) 분석. 복잡한 분석/아키텍처/스펙/API/DB 모델 필요 → PM 워커 먼저 spawn 해 설계 산출물 받은 뒤 phase plan 에 반영. 단순 fix·refactor 는 PM 생략 가능 — leader 가 직접 phase plan.
2. 타입별 가이드 (${workflows_dir}/<type>.md) 의 'Phase 템플릿' 절을 골격으로 \`.orch/runs/${mp_id}/phases.md\` 작성. 헤더에 \`## 타입: <feature|bug|refactor>\` 한 줄 명시. 권장 형식:
   \`\`\`
   # ${issue_display} Phase Plan

   ## Phase 1: <목표 한 줄>
   - 사용 워커: <e.g. ${mp_id}/server feat>
   - 산출물: <e.g. PR #N>
   - 완료 기준: <e.g. PR merged + 로컬 동기화>
   - 의존: 없음

   ## Phase 2: <목표 한 줄>
   - 사용 워커: ...
   - 산출물: ...
   - 완료 기준: ...
   - 의존: Phase 1 완료
   \`\`\`
3. phase plan 본문을 orch 로 송신 — **라벨 \`[phase-plan <issue_id>]\` 필수** (orch 가 이 라벨로 컨펌 절차 트리거):
   \`\`\`
   bash -c \"\\\$ORCH_BIN_DIR/send.sh orch <<'ORCH_MSG'
   [phase-plan ${issue_display}]
   <phases.md 본문 — 작업 타입 헤더 포함>
   ORCH_MSG\"
   \`\`\`
4. orch 는 **반드시 AskUserQuestion TUI** 로 사용자 컨펌 받음 (GO / 수정 / 취소 3택) — plain text 답신 아님. orch 가 leader 에 forward 하는 응답은 라벨 형식 고정:
   - \`[plan-confirm] GO\` → phase 1 진입.
   - \`[plan-revise] <notes>\` → phases.md 를 notes 반영해 갱신, **다시 [phase-plan] 송신 (라운드 N+1)**. notes 무시한 채 진행 금지.
   - \`[plan-cancel] <사유>\` → \`/orch:issue-down ${issue_display}\` 호출해 cascade kill.

   **\`[plan-confirm] GO\` 받기 전까지 워커 spawn / 개발 진행 금지** — 사용자 컨펌이 곧 개발 시작 권한.
5. **항상 현재 phase 의 워커만 spawn. 다음 phase 워커는 현재 phase 완료 보고 (PR merged + 로컬 동기화) 후 spawn.** 동시 다중 phase 진행 금지 — phase 간 의존이 없다고 보일 때도 사용자가 흐름을 따라가도록 순차 유지.
6. phase 완료 시마다 orch 에 \`[phase-done <n>]\` 짧은 보고 → 다음 phase 진입.

[워커 spawn — 3 역할]
  /orch:leader-spawn <project> [type]                    # developer (구현). worker_id=<issue_id>/<project>.
  /orch:leader-spawn <project> [type] --role pm          # PM (설계: 분석·아키텍처·스펙·API·DB 모델). worker_id=<issue_id>/pm.
  /orch:review-spawn <project> <pr>                      # reviewer (코드 리뷰).

type: feat | fix | refactor | chore | docs | test (dev 기본 feat / pm 기본 docs).

**phase plan 사용자 컨펌 전 워커 spawn 금지** — PM 도 spawn 전에 phase plan 에 \"Phase 0: 분석/설계\" 로 명시하고 컨펌 받는다 (PM 생략하는 단순 MP 는 Phase 1 부터).

[메시지 — Hub-and-Spoke]
- 산하 지시: /orch:send ${mp_id}/<role> '<지시>' (<role> = project alias 또는 pm)
- orch 보고: /orch:send orch '<요약>'
- 워커끼리 / 다른 MP / 다른 프로젝트 직접 통신 차단됨 — 의존 생기면 leader 라우팅 또는 orch escalate.
- **따옴표·줄바꿈·백틱 메시지는** Bash heredoc 필수:
    bash -c \"\$ORCH_BIN_DIR/send.sh <target> <<'ORCH_MSG'
    본문
    ORCH_MSG\"
  슬래시 /orch:send 는 \$ARGUMENTS 가 셸 파서 깨뜨려 특수문자 실패. \$ORCH_BIN_DIR 자동 export 됨.

[Direction Check 라우팅 — PM 산출물 필수 컨펌]
PM 으로부터 \`[direction-check]\` 라벨 메시지 받으면:
1. 즉시 본문 그대로 orch 로 forward: \`/orch:send orch '[direction-check from ${mp_id}/pm] <본문>'\` (heredoc 권장).
2. orch → leader inbox 로 사용자 답신 도착 → PM 으로 forward.
3. **그 사이 PM 산출물에 의존하는 developer/reviewer spawn 보류** — 사용자 GO 전 후속 워커 차단.
4. PM 이 큰 결정마다 재발송할 수 있음 — 매번 같은 절차로 forward.

본문 임의 요약·삭제 금지. leader 의 의견은 별도 메시지로 첨부 가능하나 PM 원문은 그대로.

[PR 4단계]
1. **CI**: 워커가 \`gh pr checks <pr> --watch --required\` 로 자기 책임. 통과하면 'PR #N ready for review + URL' 답신.
2. **리뷰**: ready 받으면 즉시 /orch:review-spawn <project> <pr>. reviewer 답신은 \`[review PR #N] LGTM\` 또는 \`needs-changes\` + 코멘트.
   - **needs-changes** → 답신 그대로 작업 워커에 라우팅 → 수정 후 're-review please' → 다시 review-spawn (라운드 N).
   - **LGTM** → 답신 그대로 작업 워커에 라우팅. 워커가 자동으로 wait-merge.sh 진입 (별도 '머지 대기' 지시 불필요).
   ⚠ LGTM 라우팅 후 워커가 wait-merge 안 들어가고 멈춰 있으면 \"\\\$ORCH_BIN_DIR/wait-merge.sh <pr> 실행\" 명시 트리거.
3. **머지 대기**: 워커 wait-merge.sh 30s 폴링. 사용자 머지 시 'PR #N merged' 답신 후 자동 종료. exit 1 / 2 면 워커 보고 → escalate.
4. **종료** (REPORT 본인 생성 후 cascade shutdown):
   a. 모든 워커 종료 확인.
   b. scope dump → REPORT-data.md:
        \`bash -c '\$ORCH_BIN_DIR/report.sh ${mp_id} > '\"\$(\$ORCH_BIN_DIR/lib.sh; orch_scope_dir ${mp_id} 2>/dev/null)\"'/REPORT-data.md'\`
        (또는 scope_dir 알면 직접 경로. \`/orch:report\` 슬래시도 가능)
   c. REPORT-data.md 해석 → \`render_report.py\` 스키마 JSON (/tmp/orch-report-${mp_id}.json) — 7 섹션 narrative 포함.
   d. HTML 렌더: \`python3 \$ORCH_BIN_DIR/render_report.py /tmp/orch-report-${mp_id}.json <scope_dir>/REPORT.html\`
   e. \`/orch:issue-down ${mp_id}\` → cascade kill + worktree 정리 + scope archive (REPORT-data.md + REPORT.html 자동 포함) + leader 자기 pane 종료.

   leader 가 c-d 단계를 깜빡해도 b 는 issue-down 이 안전망으로 다시 생성. REPORT.html 만 누락 가능 — 사용자가 archive 보고 \`/orch:report <mp_id>\` 수동 호출로 복구.

[테스트·컨텍스트]
- 크로스-프로젝트 E2E SKIP — 후속 이슈 메모. 워커 작업 독립 가정.
- 컨텍스트 150k 넘으면 보고 직후 /compact (워커에도 같은 가이드 전달).

[Worker→Leader 차단 질문 라우팅]
워커가 메시지에 \`[question:<q-id>]\` 마커를 달면 wait-reply.sh 로 답 대기 중이라는 의미. 즉시 응답 (heredoc 본문 첫 줄에 \`[reply:<q-id>]\`) 을 보내야 워커가 막힘 풀고 진행. 결정이 사용자 차원이면 그대로 orch 로 forward 한 뒤 사용자 답을 받아 같은 \`[reply:<q-id>]\` 로 워커에 송신. 답 미루지 말 것 — 워커는 그 사이 어떤 마디도 진행 안 함.

[금지]
- 리뷰 없이 머지 대기로 점프 금지 — 깨끗한 컨텍스트 reviewer 가 안전망.
- 워커 보고 없이 'PR 만들었으니 사용자가 머지' 식 종결 금지.
- phase plan 사용자 GO 받기 전에 워커 spawn 금지.
- 한 번에 다중 phase 워커 spawn 금지 — 항상 현재 phase 하나.

지금 [셋업] 1~3 + [작업 타입 판별] + [Phase Plan] 1~3 을 끝낸 뒤 phase plan 을 /orch:send orch 로 보고하세요. 사용자 GO 받기 전 워커 spawn 금지."

orch_send_keys_line "$leader_pane" "$first_msg" \
    || echo "WARN: leader first_msg 송신 실패 (pane=$leader_pane)" >&2

echo "OK leader=$mp_id pane=$leader_pane window=$leader_window"
echo "  scope_dir: $scope_dir"

# Slack 알림 — leader 가 막 떴고 plan 메시지를 곧 orch 로 송신할 예정.
"${LIB_DIR}/notify-slack.sh" mp_select "$mp_id" "leader 떴음 — 곧 plan 컨펌 메시지 도착" || true
