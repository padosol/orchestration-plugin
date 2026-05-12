#!/usr/bin/env bash
# /orch:leader-spawn <project-alias> [type] [--role pm|dev]
# leader (<issue_id>) 가 호출. 자기 이슈 산하 워커를 띄운다.
# --role dev (기본): 구현 담당 워커. worker_id=<issue_id>/<project>.
# --role pm:        분석·아키텍처·스펙·API·데이터 모델 담당. worker_id=<issue_id>/pm (단일).

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

usage() {
    cat >&2 <<EOF
사용법: /orch:leader-spawn <project-alias> [type] [--role pm|dev]
  project-alias: settings.json 의 projects 키 (예: server, ui, repo)
  type: feat | fix | refactor | chore | docs | test
        (기본: dev 는 feat / pm 은 docs)
  --role: pm | dev (기본 dev)
    dev — 구현 담당. worker_id=<issue_id>/<project>.
    pm  — 분석·시스템 아키텍처·프로젝트 계획·기술 문서·API 스펙·데이터 모델.
          worker_id=<issue_id>/pm (한 이슈 당 단일). 분석 직후 mandatory direction-check.
EOF
}

role="dev"
positional=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --role=*) role="${1#--role=}" ;;
        --role) shift; role="${1:-}" ;;
        -h|--help) usage; exit 0 ;;
        *) positional+=("$1") ;;
    esac
    shift
done

case "$role" in
    pm|dev) ;;
    *) echo "ERROR: 잘못된 role '$role' (pm|dev)" >&2; usage; exit 2 ;;
esac

if [ "${#positional[@]}" -lt 1 ]; then
    usage
    exit 2
fi

project="${positional[0]}"
type_given="${positional[1]:-}"
if [ -n "$type_given" ]; then
    type="$type_given"
elif [ "$role" = "pm" ]; then
    type="docs"
else
    type="feat"
fi

case "$type" in
    feat|fix|refactor|chore|docs|test) ;;
    *) echo "ERROR: 잘못된 type '$type' (feat|fix|refactor|chore|docs|test)" >&2; exit 2 ;;
esac

orch_settings_require || exit 2

self="$(orch_detect_self 2>/dev/null || true)"
self_kind="$(orch_wid_kind "${self:-}")"
if [ "$self_kind" != "leader" ]; then
    echo "ERROR: /orch:leader-spawn 은 leader (<issue_id>) pane 에서만 호출 가능 (현재: ${self:-unknown})" >&2
    exit 2
fi

# leader 의 자기 식별자 = 사용자가 issue-up 에 넘겼던 값 그대로 (예: MP-13, PROJ-456, 142).
# 코드 호환 위해 변수명 mp_id 유지.
mp_id="$self"

if ! orch_settings_project_exists "$project"; then
    echo "ERROR: settings.json에 프로젝트 '$project' 없음" >&2
    echo "  사용 가능: $(orch_settings_projects | tr '\n' ' ')" >&2
    echo "  새 프로젝트 추가하려면 /orch:setup --update" >&2
    exit 2
fi

if [ "$role" = "pm" ]; then
    worker_id="${mp_id}/pm"
else
    worker_id="${mp_id}/${project}"
fi
if orch_worker_exists "$worker_id"; then
    echo "ERROR: $worker_id 이미 떠 있음" >&2
    exit 2
fi

project_path="$(orch_settings_project_field "$project" path)"
[ -d "$project_path" ] || { echo "ERROR: project path '$project_path' 없음" >&2; exit 2; }

base_branch="$(orch_settings_project_base_branch "$project")"

# 브랜치·worktree 이름: issue_id 그대로 사용 (0.13.0~). 이전엔 'MP-<num>' 으로 강제 변환됐다.
if [ "$role" = "pm" ]; then
    branch_name="${type}/${mp_id}-pm"
else
    branch_name="${type}/${mp_id}"
fi

worktrees_dir="$(orch_scope_worktrees_dir "$mp_id")"
if [ "$role" = "pm" ]; then
    worktree_path="${worktrees_dir}/${mp_id}/${project}/pm"
else
    worktree_path="${worktrees_dir}/${mp_id}/${project}/${type}"
fi
mkdir -p "$(dirname "$worktree_path")"

if [ -d "$worktree_path" ]; then
    echo "INFO: worktree '$worktree_path' 이미 존재 — 재사용"
else
    echo "INFO: fetch origin/$base_branch from $project_path"
    git -C "$project_path" fetch origin "$base_branch" 2>&1 | tail -5 || true

    # origin/<base_branch> 가 실제로 없으면 fail-loud (silent || true 로 묵살하지 않음).
    # 없으면 잘못된 base 에서 worktree 가 만들어지거나 (HEAD 기준), 'invalid reference' 로 죽는다.
    if ! git -C "$project_path" rev-parse --verify --quiet "refs/remotes/origin/$base_branch" >/dev/null; then
        cat >&2 <<EOF
ERROR: origin/$base_branch 가 $project_path 에 없음 — worktree 생성 불가.
  - settings.json projects.$project.default_base_branch 가 잘못됐을 가능성. 갱신 예시:
      jq '.projects.$project.default_base_branch = "main"' .orch/settings.json
  - 또는 /orch:setup --update 로 git remote 자동 감지값 다시 받기.
  - 사용 가능한 원격 브랜치: $(git -C "$project_path" branch -r 2>/dev/null | sed 's/^ *//' | tr '\n' ' ')
EOF
        exit 2
    fi

    if git -C "$project_path" show-ref --verify --quiet "refs/heads/$branch_name"; then
        echo "INFO: 브랜치 $branch_name 이미 존재 — attach"
        git -C "$project_path" worktree add "$worktree_path" "$branch_name"
    else
        git -C "$project_path" worktree add "$worktree_path" -b "$branch_name" "origin/$base_branch"
    fi
fi

# tmux: mp_id 이름 윈도우 있으면 split, 없으면 새로 생성
mp_window="$(tmux list-windows -t "$ORCH_TMUX_SESSION" -F '#{window_id} #W' 2>/dev/null \
    | awk -v n="$mp_id" '$2==n {print $1}' | head -n1)"

if [ -z "$mp_window" ]; then
    ids="$(orch_new_window "$mp_id" "$worktree_path")"
    read -r mp_window worker_pane <<<"$ids"
else
    worker_pane="$(orch_split_in_window "$mp_window" "$worktree_path")"
fi

if [ -z "$worker_pane" ]; then
    echo "ERROR: worker pane 생성 실패" >&2
    exit 2
fi

orch_worker_register "$worker_id" "worker" "$mp_window" "$worker_pane" "$worktree_path" "$project"

tmux send-keys -t "$worker_pane" "export ORCH_WORKER_ID=${worker_id} ORCH_BIN_DIR=${LIB_DIR} && claude" Enter
sleep 4

desc="$(orch_settings_project_field "$project" description)"
stack="$(orch_settings_project_field "$project" tech_stack)"
plugin_root_ls="$(dirname "$LIB_DIR")"
guidelines_path="${plugin_root_ls}/references/coding-guidelines.md"
protocols_path="${plugin_root_ls}/references/orch-protocols.md"

if [ "$role" = "pm" ]; then
    first_msg="너는 ${worker_id} 워커 (PM 역할) 다. ${mp_id} 의 분석·시스템 아키텍처·기술 문서·API 스펙·데이터 모델 **설계** 책임. 코드 직접 구현은 developer 워커 담당, **phase 계획·실행 순서는 leader (${mp_id}) 가 소유**.

[컨텍스트 — spawn 시 주입]
- alias: $project (worktree host. PM 은 필요 시 다른 project 코드도 \`git -C <abs-path>\` / \`Read <abs-path>\` 로 참조 — cd 금지)
- worktree: $worktree_path (현재 cwd) / branch: $branch_name (base: origin/$base_branch)
- tech: $stack / 설명: $desc
- leader: ${mp_id}

[필수 — 첫 마디로 Skill 로딩]
1) Skill 도구 invoke: **orch-pm**. 페르소나·책임·direction-check 차단·산출물 PR 4단계·종료 절차 전체가 본 SKILL 에 담겨 있다.
2) Skill 로드 실패 시 fallback: \`Read ${plugin_root_ls}/skills/orch-pm/SKILL.md\` 1회. 본문 그대로 따른다.
3) 공통 운영 규약 단일 source: \`Read ${protocols_path}\` 1회 (hub-and-spoke / wait-reply qid / HOLD / PR 4단계 / shutdown).

[Hard Guards — 본 first_msg 만으로도 절대 어기지 말 것]
1. **사용자 컨펌 없이 산출물 finalize / commit / push 금지.** 분석 직후 mandatory \`[direction-check]\` + \`[question:<qid>]\` 송신 → \`bash \\\$ORCH_BIN_DIR/wait-reply.sh <qid>\` 차단 대기. 답 반영 후에야 산출물 확정.
2. direction-check 단계 생략 금지 — 추측 진행이 PM 의 최대 함정.
3. developer / reviewer 와 직접 통신 금지 — 모든 라우팅은 leader (${mp_id}) 경유.
4. phase 계획·실행 순서는 leader 소유. PM 은 산출물 (사양 / 문서 / 스키마 / 다이어그램) 만 책임.

[진입 액션]
- 위 1) Skill 도구 invoke (orch-pm) → 2) orch-protocols.md Read → \`/orch:check-inbox\` 로 leader 의 첫 지시 (이번 이슈 분석 범위) 받아 시작.
- 첫 산출물은 \`[direction-check]\` 메시지를 목표로."
else
    first_msg="너는 ${worker_id} 워커다. ${stack} 스택을 다루며 분석 우선 → 최소 침습 (Surgical) 편집 → 변경분 한정 테스트 → 짧은 보고 패턴으로 일한다.

[컨텍스트 — spawn 시 주입]
- alias: $project / path: $project_path
- worktree: $worktree_path (현재 cwd) / branch: $branch_name (base: origin/$base_branch)
- tech: $stack / 설명: $desc
- leader: ${mp_id}
- 브랜치 type: $type (feat | fix | refactor | chore | docs | test 중 하나)

[필수 — 첫 마디로 Skill 로딩]
1) Skill 도구 invoke: **orch-developer-worker**. 페르소나·HOLD 체크포인트·차단 질문·PR 4단계·worker-shutdown 절차 전체가 본 SKILL 에 담겨 있다.
2) Skill 로드 실패 시 fallback: \`Read ${plugin_root_ls}/skills/orch-developer-worker/SKILL.md\` 1회. 본문 그대로 따른다.
3) 공통 운영 규약 단일 source: \`Read ${protocols_path}\` 1회 (hub-and-spoke / wait-reply qid / HOLD / PR 4단계 / shutdown).
4) 분석 단계 시작 시 \`Read ${guidelines_path}\` 1회 — 4원칙 (Think Before / Simplicity / Surgical / Goal-Driven) 의식적 적용.

[Hard Guards — 본 first_msg 만으로도 절대 어기지 말 것]
1. **모호한 spec 은 추측 진행 금지** — leader (${mp_id}) 에 \`[question:<qid>]\` + \`wait-reply.sh\` 차단 대기. 답 도착 전 다른 마디 진행 금지.
2. **HOLD 체크포인트**: (a) 분석 → 편집 전환 직전 / (b) push 직전 — 두 마디에서 \`/orch:check-inbox\` 1회. HOLD / 취소 발견 시 즉시 중단 후 leader ack.
3. **다른 워커 / 다른 프로젝트 직접 통신 금지** — 모든 라우팅은 leader 경유. send.sh 가드가 거부.
4. **PR 4단계 마지막 자기 종료 의무** — \`bash \\\$ORCH_BIN_DIR/worker-shutdown.sh\` 한 번. \`exit\` 키 입력 금지.

[진입 액션]
- 위 1) Skill 도구 invoke (orch-developer-worker) → 2) orch-protocols.md Read → 3) coding-guidelines.md Read → \`/orch:check-inbox\` 로 leader 의 첫 지시 받아라."
fi

orch_send_keys_line "$worker_pane" "$first_msg" \
    || echo "WARN: worker first_msg 송신 실패 (pane=$worker_pane)" >&2

echo "OK worker=$worker_id role=$role pane=$worker_pane window=$mp_window"
echo "  worktree: $worktree_path"
echo "  branch:   $branch_name"
