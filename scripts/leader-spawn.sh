#!/usr/bin/env bash
# /orch:leader-spawn <project-alias> [type]
# leader (mp-NN) 가 호출. 자기 MP 산하 프로젝트 워커를 띄운다.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

if [ "$#" -lt 1 ]; then
    cat >&2 <<EOF
사용법: /orch:leader-spawn <project-alias> [type]
  project-alias: settings.json 의 projects 키 (예: server, ui, repo)
  type: feat | fix | refactor | chore | docs (기본 feat)
EOF
    exit 2
fi

project="$1"
type="${2:-feat}"

case "$type" in
    feat|fix|refactor|chore|docs|test) ;;
    *) echo "ERROR: 잘못된 type '$type' (feat|fix|refactor|chore|docs|test)" >&2; exit 2 ;;
esac

orch_settings_require || exit 2

self="$(orch_detect_self 2>/dev/null || true)"
self_kind="$(orch_wid_kind "${self:-}")"
if [ "$self_kind" != "leader" ]; then
    echo "ERROR: /orch:leader-spawn 은 leader (mp-NN) pane 에서만 호출 가능 (현재: ${self:-unknown})" >&2
    exit 2
fi

mp_id="$self"

if ! orch_settings_project_exists "$project"; then
    echo "ERROR: settings.json에 프로젝트 '$project' 없음" >&2
    echo "  사용 가능: $(orch_settings_projects | tr '\n' ' ')" >&2
    echo "  새 프로젝트 추가하려면 /orch:setup --update" >&2
    exit 2
fi

worker_id="${mp_id}/${project}"
if orch_worker_exists "$worker_id"; then
    echo "ERROR: $worker_id 이미 떠 있음" >&2
    exit 2
fi

project_path="$(orch_settings_project_field "$project" path)"
[ -d "$project_path" ] || { echo "ERROR: project path '$project_path' 없음" >&2; exit 2; }

base_branch="$(orch_settings_project_base_branch "$project")"

issue_num="${mp_id#mp-}"
branch_name="${type}/MP-${issue_num}"

worktrees_dir="$(orch_scope_worktrees_dir "$mp_id")"
worktree_path="${worktrees_dir}/MP-${issue_num}/${project}/${type}"
mkdir -p "$(dirname "$worktree_path")"

if [ -d "$worktree_path" ]; then
    echo "INFO: worktree '$worktree_path' 이미 존재 — 재사용"
else
    echo "INFO: fetch origin/$base_branch from $project_path"
    git -C "$project_path" fetch origin "$base_branch" 2>&1 | tail -5 || true

    # origin/<base_branch> 가 실제로 없으면 fail-loud (silent || true 로 묵살하지 않음).
    # 없으면 잘못된 base 에서 worktree 가 만들어지거나 (HEAD 기준), 'invalid reference' 로 죽는다.
    if ! git -C "$project_path" rev-parse --verify --quiet "refs/remotes/origin/$base_branch" >/dev/null; then
        global_default="$(orch_settings_global default_base_branch 2>/dev/null || true)"
        cat >&2 <<EOF
ERROR: origin/$base_branch 가 $project_path 에 없음 — worktree 생성 불가.
  - 이 프로젝트의 기본 브랜치가 다르면 settings.json projects.$project.default_base_branch 로 override:
      jq '.projects.$project.default_base_branch = "main"' .orch/settings.json
  - 워크스페이스 default: ${global_default:-develop} (글로벌 .default_base_branch)
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

orch_worker_register "$worker_id" "worker" "$mp_window" "$worker_pane" "$worktree_path"

tmux send-keys -t "$worker_pane" "export ORCH_WORKER_ID=${worker_id} ORCH_BIN_DIR=${LIB_DIR} && claude" Enter
sleep 4

desc="$(orch_settings_project_field "$project" description)"
stack="$(orch_settings_project_field "$project" tech_stack)"
guidelines_path="$(dirname "$LIB_DIR")/references/coding-guidelines.md"

first_msg="너는 ${worker_id} 워커다. 10년차 시니어 소프트웨어 엔지니어로서 ${stack} 스택을 다루며, 분석 우선 → 최소 침습 (surgical) 편집 → 변경분 한정 테스트 → 짧은 보고 패턴으로 일한다. 모호한 spec 은 추측 진행 금지하고 leader 에 escalate.

[컨텍스트]
- alias: $project / path: $project_path
- worktree: $worktree_path (현재 cwd) / branch: $branch_name (base: origin/$base_branch)
- tech: $stack / 설명: $desc

[작업]
- leader($mp_id) 가 곧 inbox 에 작업 지시. /orch:check-inbox 로 받아 처리.
- 코드 수정은 worktree 안에서. 커밋은 safe-commit 스킬.
- 분석 단계 시작 시 ${guidelines_path} 1회 Read — 4원칙 (Think Before / Simplicity / Surgical / Goal-Driven) 의식적 적용.

[HOLD 체크포인트 — 필수]
leader 의 HOLD/취소가 묻히지 않도록 다음 두 마디에서 /orch:check-inbox 1회:
1. **분석 → 편집 전환 직전** — 코드 수정 시작 전. spec 재검토 + HOLD 도착 여부 확인.
2. **push 직전** — 로컬 커밋 끝났지만 origin push 전. push 후엔 PR/CI 비용 발생.
HOLD/취소/방향 전환 발견 → 즉시 중단, leader 에 ack 후 다음 지시 대기. 새 메시지 0건 → 그대로 진행.

[브랜치 prefix — spawn 시 type=$type]
작업 내용이 다른 type 에 더 가까우면 leader 보고 후 재spawn 요청 (직접 rename 금지).
- feat 신규 기능 / fix 버그 / refactor 동작 동일 구조 개선 / chore 코드 외 부속 (audit, deps, CI) / docs 문서·주석 / test 테스트만

[메시지 — Hub-and-Spoke]
- leader 답신: /orch:send $mp_id '<답>'
- 다른 워커에 묻고 싶어도 leader 에게 — leader 라우팅. 직접 통신은 send.sh 차단.
- **따옴표·줄바꿈·백틱 메시지는** Bash heredoc 필수:
    bash -c \"\$ORCH_BIN_DIR/send.sh $mp_id <<'ORCH_MSG'
    본문
    ORCH_MSG\"
  \$ORCH_BIN_DIR 자동 export 됨. 슬래시 /orch:send 는 특수문자에서 깨짐.

[사용자 prompt 모호 응답 → escalate]
auto-mode classifier 가 사용자 prompt 띄우고 답이 \"보류\"·\"잠시\"·\"음...\" 등 모호하면 추측 진행 금지. leader 에 사유 명시 요청 (보류 사유 / PR 분리 / 재검토 / 단순 확인 중 어느 것?). 명확한 GO·STOP 아니면 대기.

[테스트 — 변경분 한정]
전체 빌드·전체 테스트 금지 (\`./gradlew build\` / \`pnpm test\` 전체 실행 금지). 변경한 파일/클래스/모듈만:
- Gradle: \`./gradlew :module:test --tests <변경 클래스>\`
- jest: \`pnpm test -- --findRelatedTests <변경 파일>\`
- typecheck \`pnpm tsc --noEmit\` 정도는 빠르므로 OK.
- 크로스-프로젝트 E2E SKIP. 의존 보이면 leader 보고.

[컨텍스트] 150k 넘으면 작업 마디(커밋/보고 직후) 에서 /compact.

[PR 4단계]
1. **CI**: 커밋 push gh pr create 후 \`gh pr checks <pr> --watch --required\` 블록 대기. 실패면 \`gh run view <run-id> --log-failed | head -200\`. 자기 영역이면 직접 수정 push.
2. **리뷰**: 통과 후 leader 에 'PR #N ready for review + URL' 답신.
   - 받은 메시지에 \`needs-changes\` → 수정 push → 're-review please' 답신 → 반복.
   - 받은 메시지에 \`LGTM\` → **즉시 3 진입** (leader 추가 지시 기다리지 말 것).
3. **머지 대기**: \`bash \$ORCH_BIN_DIR/wait-merge.sh <pr-num>\` 30s 폴링.
   - exit 0 (MERGED) → leader 에 'PR #N merged' → 4 진입.
   - exit 1 (CLOSED) / exit 2 (timeout) → leader 보고 후 대기.
4. **자기 종료** (필수): \`bash \$ORCH_BIN_DIR/worker-shutdown.sh\` 한 번. registry 해제 + pane kill 한 번에. \`exit\` 키 입력 금지 (Claude Code 떠 있어 셸에 안 닿음). 이 명령 이후 응답 못 받는다 (정상).

준비되면 /orch:check-inbox 로 첫 지시 받아라."

orch_send_keys_line "$worker_pane" "$first_msg" \
    || echo "WARN: worker first_msg 송신 실패 (pane=$worker_pane)" >&2

echo "OK worker=$worker_id pane=$worker_pane window=$mp_window"
echo "  worktree: $worktree_path"
echo "  branch:   $branch_name"
