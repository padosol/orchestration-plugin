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

base_branch="$(orch_settings_global default_base_branch)"
[ -n "$base_branch" ] || base_branch="develop"

issue_num="${mp_id#mp-}"
branch_name="${type}/MP-${issue_num}"

worktrees_dir="$(orch_scope_worktrees_dir "$mp_id")"
worktree_path="${worktrees_dir}/MP-${issue_num}/${project}/${type}"
mkdir -p "$(dirname "$worktree_path")"

if [ -d "$worktree_path" ]; then
    echo "INFO: worktree '$worktree_path' 이미 존재 — 재사용"
else
    echo "INFO: fetch origin/$base_branch from $project_path"
    git -C "$project_path" fetch origin "$base_branch" >/dev/null 2>&1 || true

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

first_msg="너는 ${worker_id} 워커다.

[프로젝트 컨텍스트]
- alias: $project
- path: $project_path
- worktree: $worktree_path (현재 cwd)
- branch: $branch_name (base: origin/$base_branch)
- tech_stack: $stack
- 설명: $desc

[작업]
- leader($mp_id) 가 곧 inbox에 작업 지시를 보낸다 — /orch:check-inbox 로 받아 처리.
- 코드 수정은 worktree 안에서. 커밋은 safe-commit 스킬 사용.

[메시지 규칙 — Hub-and-Spoke]
- 모든 외부 통신은 leader($mp_id) 를 통한다.
- leader 에 답신: /orch:send $mp_id '<답>'
- 다른 프로젝트(다른 worker)에 질문이 필요해도 leader 에게 보내라 — leader가 라우팅.
- 직접 다른 worker / 다른 mp-XX / orch 에 보내는 건 send.sh가 차단한다.

[중요 — 따옴표·줄바꿈·백틱이 들어간 메시지는 슬래시 명령 대신 Bash heredoc 사용]
  bash -c \"\$ORCH_BIN_DIR/send.sh $mp_id <<'ORCH_MSG'
  여러 줄
  '따옴표' 와 \\\`백틱\\\` 그대로 전달
  ORCH_MSG\"
  \$ORCH_BIN_DIR 는 워커 launch 시 자동 export 됨. 'send.sh' 만 쓰면 PATH 못 찾아 실패하니 반드시 \$ORCH_BIN_DIR 접두 사용.
  간단한 메시지(따옴표·줄바꿈 없음)는 /orch:send 슬래시로 충분.

[테스트 범위 — 변경분 한정]
- **변경한 파일/클래스/모듈에 한정한 테스트만** 수행. 전체 빌드·전체 테스트는 CI 단계에서 돌린다 (로컬에서 \`./gradlew build\` / \`pnpm test\` 전체 실행 금지 — 시간 낭비).
- 예시 (대상 한정 실행):
  - Gradle: \`./gradlew :module:test --tests <변경 클래스명>\` 또는 \`./gradlew :module:test --tests '<패키지>.<클래스>*'\`
  - pnpm/jest: \`pnpm test -- --findRelatedTests <변경 파일>\` 또는 \`pnpm test -- <변경 디렉토리>\`
  - typecheck: \`pnpm tsc --noEmit\` 정도는 빠르므로 OK
- 크로스-프로젝트 E2E 는 로컬 환경 한계로 SKIP — 발견된 의존 케이스는 후속 이슈 메모로만 남기고 본 작업에 묶지 말 것.
- 다른 워커 작업은 독립이라고 가정. 진짜 의존이 보이면 leader 에 보고해 분해 받기.
- 변경 영향이 큰 (스키마 / 공통 lib) 경우만 영향 범위 모듈 단위 테스트 — 전체 X.

[컨텍스트 관리]
- 컨텍스트 사용량이 150k 토큰 넘으면 작업 마디(커밋/보고 직후)에서 /compact 실행. 도구 결과가 큰 경우(파일 통째 read, 긴 grep 등) 더 빠르게.

[PR 라이프사이클 — 4단계]

1. **CI 통과까지 직접 대기**
   - 작업 완료 → 커밋 → push → \`gh pr create\` → \`gh pr checks <pr-num> --watch --required\` 블록 대기
   - watch 가 비0 으로 끝나면 실패 로그: \`gh run view <run-id> --log-failed | head -200\`
   - 자기 영역 실패면 직접 수정 후 push, 통과까지 다시 watch
   - 모호한 실패(인프라 등)는 leader 에 로그 발췌 동봉
   - (mp-9 checkstyle 사일런트 실패 재발 방지)

2. **리뷰 대기 → 보고**
   - 모든 필수 체크 통과 → leader 에 **'PR #N ready for review' + URL** 답신
   - leader 가 reviewer 워커를 띄워 코드 리뷰 후 코멘트를 너에게 라우팅한다
   - 받은 메시지가 \`needs-changes\` 또는 코멘트 포함 → 수정 → 추가 커밋 push → leader 에 're-review please' 답신
   - 받은 메시지가 \`LGTM\` 포함 → **즉시 3번(머지 대기) 진입**. leader 의 추가 '머지 대기' 지시 기다리지 말 것.
   - LGTM 받을 때까지 반복 (라운드 N)

3. **머지 대기 (LGTM 메시지 즉시 진입 — 추가 지시 불필요)**
   - 다음 명령으로 블록 폴링:
       bash \$ORCH_BIN_DIR/wait-merge.sh <pr-num>
   - 30s 간격 폴링. 사용자가 PR 머지하면 즉시 풀려서 exit 0 반환.
   - 결과 처리:
     - **exit 0 (MERGED)** → leader 에 'PR #N merged' 답신 → 4번으로
     - **exit 1 (CLOSED 미머지)** → leader 에 'PR #N closed without merge' 보고 후 다음 지시 대기
     - **exit 2 (timeout 24h)** → leader 에 'PR #N merge wait timeout' 보고 후 대기

   ⚠ LGTM 받았는데 wait-merge.sh 호출 안 하고 멈춰 있으면 머지 사이클이 stuck 된다. 받은 메시지에 \`LGTM\` 있으면 다른 작업 끼우지 말고 바로 명령 실행.

4. **자기 pane 종료 (필수)**
   - merged 보고 직후 다음 명령 한 번:
       bash \$ORCH_BIN_DIR/worker-shutdown.sh
   - registry 해제 + tmux pane kill 까지 한 번에 처리한다. \`exit\` 키 입력은 Claude Code 가 떠 있어서 셸에 닿지 않으므로 사용 금지.
   - 이 명령 이후 응답을 받지 못한다 (자기 pane 이 죽음). 정상 동작이다.

준비되면 /orch:check-inbox 로 첫 지시를 받아라."

tmux send-keys -t "$worker_pane" "$first_msg"
sleep 0.3
tmux send-keys -t "$worker_pane" Enter

echo "OK worker=$worker_id pane=$worker_pane window=$mp_window"
echo "  worktree: $worktree_path"
echo "  branch:   $branch_name"
