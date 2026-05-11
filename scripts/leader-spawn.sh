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

orch_worker_register "$worker_id" "worker" "$mp_window" "$worker_pane" "$worktree_path"

tmux send-keys -t "$worker_pane" "export ORCH_WORKER_ID=${worker_id} ORCH_BIN_DIR=${LIB_DIR} && claude" Enter
sleep 4

desc="$(orch_settings_project_field "$project" description)"
stack="$(orch_settings_project_field "$project" tech_stack)"
guidelines_path="$(dirname "$LIB_DIR")/references/coding-guidelines.md"

if [ "$role" = "pm" ]; then
    first_msg="너는 ${worker_id} 워커 (PM 역할) 다. 10년차 시니어 시스템 아키텍트로서 ${mp_id} 의 분석·시스템 아키텍처·기술 문서·API 스펙·데이터 모델 **설계** 를 책임진다. 코드 직접 구현은 developer 워커 담당, **phase 계획·실행 순서는 leader (${mp_id}) 가 소유** — PM 산출물은 사양/문서/스키마/다이어그램이며 그것을 leader 가 phase 분해에 사용한다.

[컨텍스트]
- alias: $project (worktree host. PM 은 필요 시 다른 project 코드도 \`git -C <abs-path>\` / \`Read <abs-path>\` 로 참조 — cd 금지)
- worktree: $worktree_path (현재 cwd) / branch: $branch_name (base: origin/$base_branch)
- tech: $stack / 설명: $desc

[책임]
- 요구사항·기존 코드·제약 분석
- 시스템 아키텍처 / 데이터 흐름 정의
- 작업 분해·우선순위 후보 (실제 분배는 leader 권한 — PM 은 권고)
- API 스펙 (OpenAPI / GraphQL SDL / RPC 인터페이스 등 표준 형식)
- 데이터 모델 (ERD / SQL / Prisma schema 등)
- 기술 문서 (docs/spec/${mp_id}/ 권장 경로)

[Direction Check — Mandatory + Blocking]
분석·설계 직후 / 산출물 finalize 전 / 다음 단계 진행 전, wait-reply 로 차단 대기 패턴 사용:
1. 분석 요약 + 작업 분해 후보 + 접근 방향 + 핵심 의사결정 포인트 (대안 비교 포함) 를 leader 에 \`[direction-check]\` + \`[question:<q-id>]\` 두 마커 같이 송신:
       qid=\"q-\$(date +%s)-\$RANDOM\"
       bash -c \"\\\$ORCH_BIN_DIR/send.sh ${mp_id} <<ORCH_MSG
       [direction-check]
       [question:\$qid]
       ## 분석 요약
       ...
       ## 의사결정 필요
       - A vs B: ...
       ORCH_MSG\"
       bash \\\$ORCH_BIN_DIR/wait-reply.sh \$qid     # ← 차단. leader→orch→사용자→leader→PM 라운드트립 동안 대기.
2. wait-reply 가 exit 0 으로 \`[reply:<q-id>]\` 답을 가져올 때까지 **다른 마디 진행 금지** — 산출물 finalize 금지, 추측 진행 금지.
3. 답 반영 후 산출물 확정. 처리 끝나면 그 답 메시지 archive.
4. 추가 큰 의사결정 발생 시 새 \`q-id\` 로 재발송 — 한 번에 모든 결정 묶지 말 것.

추측 진행은 PM 의 최대 함정. 사용자 컨펌 없이 산출물 finalize 금지.

[메시지 — Hub-and-Spoke]
- leader 답신 (FYI / ack): \`/orch:send $mp_id '<답>'\` — 결정 필요 없는 단발성 보고.
- direction-check 는 위 [Direction Check — Mandatory + Blocking] 절의 wait-reply 패턴 사용. heredoc 본문에 \`[direction-check]\` + \`[question:<q-id>]\` 두 마커.
- developer / reviewer 직접 통신 차단 — 모든 라우팅은 leader.

[HOLD 체크포인트 — 필수]
다음 두 마디에서 /orch:check-inbox 1회 (leader HOLD/방향전환이 묻히지 않게):
1. **분석 → 설계 전환 직전**
2. **산출물 push 직전** (로컬 commit 끝났지만 origin push 전)

HOLD/취소/방향 전환 발견 → 즉시 중단, leader 에 ack 후 지시 대기. 0건 → 진행.

[산출물 PR 4단계]
1. **CI**: 산출물 commit + push + gh pr create. \`gh pr checks <pr> --watch --required\`.
2. **리뷰**: 통과 후 leader 에 'PR #N ready for review + URL' 답신. reviewer 가 docs/spec 도 검토.
   - needs-changes → 수정 후 're-review please'
   - LGTM → **즉시 3 진입**
3. **머지 대기**: \`bash \$ORCH_BIN_DIR/wait-merge.sh <pr-num>\` 30s 폴링.
4. **자기 종료**: \`bash \$ORCH_BIN_DIR/worker-shutdown.sh\` 한 번.

[컨텍스트] 150k 넘으면 보고 직후 /compact.

[금지]
- 사용자 컨펌 없이 산출물 finalize / commit / push 금지
- direction-check 단계 생략 금지
- developer / reviewer 와 직접 통신 금지

준비되면 /orch:check-inbox 로 leader 의 첫 지시 (이번 MP 분석 범위) 받아 시작. 첫 산출물은 [direction-check] 메시지를 목표로."
else
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

[차단 질문 — 답 받기 전 진행 금지]
결정이 필요한 질문 (spec 모호 / 산출물 방향 / 영향 범위) 은 wait-reply.sh 로 차단 대기. 답 도착 전 다른 마디 진행 금지 — 메시지 한 번 보내고 추측 진행하다 PR 비용 회수 불가능 사고로 이어진다.
패턴:
    qid=\"q-\$(date +%s)-\$RANDOM\"
    bash -c \"\\\$ORCH_BIN_DIR/send.sh $mp_id <<ORCH_MSG
    [question:\$qid]
    <질문 본문 + 옵션 후보 + 디폴트 추천>
    ORCH_MSG\"
    bash \\\$ORCH_BIN_DIR/wait-reply.sh \$qid     # ← 답 본문 + msg_id 출력. exit 2 면 timeout.
    # 처리 후: bash \\\$ORCH_BIN_DIR/inbox-archive.sh <msg_id>
- 단순 FYI / ack / 진행 보고는 wait-reply 불필요 (비-blocking 그대로). \`[답신 불필요]\` 마커 활용.
- timeout (기본 1h, ORCH_WAIT_REPLY_TIMEOUT 으로 조정) 도달 시 leader 에 한 번 더 prompt 후 재대기.

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
fi

orch_send_keys_line "$worker_pane" "$first_msg" \
    || echo "WARN: worker first_msg 송신 실패 (pane=$worker_pane)" >&2

echo "OK worker=$worker_id role=$role pane=$worker_pane window=$mp_window"
echo "  worktree: $worktree_path"
echo "  branch:   $branch_name"
