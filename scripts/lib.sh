#!/usr/bin/env bash
# orch v2 — 2-tier hub-and-spoke 공통 함수 라이브러리.
#
# 식별자(worker_id) 형태:
#   orch                  → PM (사용자와 대화). 예약 식별자.
#   <issue_id>            → <issue_id> 팀리더. <issue_id> 는 사용자가 /orch:issue-up 에 넘긴 값 그대로
#                            sanitize 만 거친 형태 ([A-Za-z0-9_-]+, 대소문자 보존). 트래커별 예:
#                            Linear MP-13, Jira PROJ-456, GitHub 142, 자유 issue42.
#   <issue_id>/<project>  → 산하 프로젝트 워커.
#
# 0.13.0 이전: leader_id 가 `mp-NN` 으로 강제 변환됐다 (Linear 시절 잔재). 이제 트래커 무관.
# 'orch' 만 reserved — 다른 leader_id 는 사용자 이슈 키 그대로.
#
# 디스크 레이아웃:
#   .orch/settings.json                            프로젝트 메타데이터
#   .orch/inbox/<id>.md                            orch / leader 인박스
#   .orch/archive/<id>-YYYY-MM-DD.md               orch / leader 메시지 archive
#   .orch/archive/<scope>-YYYY-MM-DD/              issue-down 시 scope dir 통째 archive
#   .orch/workers/<id>.json                        orch / leader 등록
#   .orch/runs/<scope>/inbox/<role>.md             leader 산하 워커 인박스
#   .orch/runs/<scope>/archive/<role>-YYYY-MM-DD.md
#   .orch/runs/<scope>/workers/<role>.json         살아있는 워커 등록
#   .orch/runs/<scope>/workers-archive/<role>.json 종료된 워커 (worker-shutdown 이 보존, sidecar 분석용)
#   .orch/runs/<scope>/worktrees/<project>/        git worktree
#   .orch/runs/<scope>/leader-archive.md           leader inbox archive (issue-down 시 함께 archive)
#   .orch/runs/<scope>/errors.jsonl                scope 별 에러 로그
#
# 신규 issue scope 는 `.orch/runs/<scope>/` 아래에 묶인다 — 동시 진행이 많아져도 .orch 루트가
# 어수선하지 않도록 wrapper 한 단계 추가. 후방호환: 평탄 `.orch/<scope>/` 와 legacy `mp-*`
# 디렉토리도 함께 인식 — orch_scope_dir 가 모두를 본다.
#
# **inbox 빈 파일 = 처리할 메시지 없음 (정상 상태).** inbox-archive.sh 가 처리된 메시지
# 를 archive/ 로 옮긴 뒤 inbox/<role>.md 를 truncate 한다. 처리 흔적은 archive 쪽 확인.

# ─── ORCH_ROOT 추론 ───────────────────────────────────────────────────
# 우선순위:
#   1) 환경변수 ORCH_ROOT 명시
#   2) PWD 부터 부모 traverse — .orch 디렉토리가 있는 첫 위치의 ${dir}/.orch
#   3) ${PWD}/.orch (setup 시 새로 생성될 위치)
# 후방호환: 기존 워크스페이스에 .orch 가 이미 있고 위 추론이 실패해도 그대로 동작.
_orch_find_root() {
    if [ -n "${ORCH_ROOT:-}" ]; then
        printf '%s' "$ORCH_ROOT"
        return
    fi
    local d="${PWD:-$(pwd)}"
    while [ "$d" != "/" ] && [ -n "$d" ]; do
        if [ -d "$d/.orch" ]; then
            printf '%s/.orch' "$d"
            return
        fi
        d="$(dirname "$d")"
    done
    # 못 찾음 — 현재 디렉토리에 만들 예정
    printf '%s/.orch' "${PWD:-$(pwd)}"
}
ORCH_ROOT="$(_orch_find_root)"
ORCH_INBOX="${ORCH_ROOT}/inbox"
ORCH_ARCHIVE="${ORCH_ROOT}/archive"
ORCH_WORKERS="${ORCH_ROOT}/workers"
ORCH_SETTINGS="${ORCH_ROOT}/settings.json"
# errors.jsonl 은 caller scope 에 따라 결정 (orch_errors_log_path 참고).
# orch / unknown → ${ORCH_ROOT}/errors.jsonl
# <issue_id>, <issue_id>/role → ${ORCH_ROOT}/runs/<issue_id>/errors.jsonl  (issue-down 이 scope dir 째 archive)
ORCH_ERRORS_LOG="${ORCH_ROOT}/errors.jsonl"  # legacy compat — 신규 코드는 orch_errors_log_path 사용
ORCH_RUNS_DIR="${ORCH_ROOT}/runs"

# issue_id / worker role: positive regex 폐지, deny-list sanitize 로 전환.
# 단일 segment 안전성은 `orch_id_safe` 가 판정 — 공백/제어문자, shell metacharacters
# (;|&$`\), redirect/grouping/quoting (<>!(){}[]\"\'), glob (*?), tilde expansion (~),
# path traversal (..), slash 차단, 'orch' reserved, 빈 입력 거부. worker_id 는
# '<issue>/<role>' 로 정확히 1회 split 후 양쪽 모두 orch_id_safe. 트래커 자연 키
# (#, ., +, @, 등) 는 모두 통과 — leading # 은 generated shell command 안에서 항상
# single-quote 로 감싸야 shell comment 위험 회피.

# tmux 세션 — 호출자가 살아있는 세션을 따라간다.
# fallback 우선순위: env ORCH_TMUX_SESSION > current tmux > base_dir basename > "orch"
if [ -z "${ORCH_TMUX_SESSION:-}" ]; then
    if [ -n "${TMUX:-}" ]; then
        ORCH_TMUX_SESSION="$(tmux display-message -p '#S' 2>/dev/null || true)"
    fi
    if [ -z "${ORCH_TMUX_SESSION:-}" ]; then
        # ORCH_ROOT 의 부모 디렉토리 basename 사용 — base_dir 을 세션명으로 자연 연결
        _orch_base="$(dirname "$ORCH_ROOT")"
        ORCH_TMUX_SESSION="${_orch_base##*/}"
        unset _orch_base
    fi
    [ -z "${ORCH_TMUX_SESSION:-}" ] && ORCH_TMUX_SESSION="orch"
fi

# ─── Worker ID 파싱 ───────────────────────────────────────────────────

# 단일 ID 세그먼트 안전 판정 (issue_id, worker role 한쪽씩).
# 거부 사유: 빈, 'orch' reserved, 공백/제어문자, shell metacharacters, redirect/grouping/quoting,
# glob (*, ?), tilde expansion (~), path traversal('..'), slash.
# 자연 키 (#, ., +, @, alnum, -, _) 는 통과 — 단 호출자는 generated shell command 에서 항상
# single-quote 로 감싸야 함 (#  은 leading 시 shell comment 위험).
orch_id_safe() {
    local v="$1"
    [ -n "$v" ] || return 1
    [ "$v" = "orch" ] && return 1
    case "$v" in *..*) return 1 ;; esac
    [[ "$v" =~ [[:cntrl:][:space:]] ]] && return 1
    case "$v" in
        */*) return 1 ;;
        *\;*|*\|*|*\&*|*\$*|*\`*|*\\*) return 1 ;;
        *\<*|*\>*) return 1 ;;
        *\!*|*\(*|*\)*|*\{*|*\}*|*\[*|*\]*) return 1 ;;
        *\"*|*\'*) return 1 ;;
        *\**|*\?*|*~*) return 1 ;;
    esac
    return 0
}

# 출력: orch | leader | worker | invalid (항상 exit 0 — 호출자가 case로 분기)
orch_wid_kind() {
    local w="$1"
    if [ "$w" = "orch" ]; then printf 'orch'; return 0; fi
    local rest="${w#*/}"
    if [ "$rest" = "$w" ]; then
        if orch_id_safe "$w"; then printf 'leader'; else printf 'invalid'; fi
        return 0
    fi
    local issue="${w%%/*}" role="${w#*/}"
    case "$role" in */*) printf 'invalid'; return 0 ;; esac
    if orch_id_safe "$issue" && orch_id_safe "$role"; then
        printf 'worker'
    else
        printf 'invalid'
    fi
}

# scope: orch→empty, <issue_id>→<issue_id>, <issue_id>/x→<issue_id>
orch_wid_scope() {
    local w="$1" kind
    kind="$(orch_wid_kind "$w")"
    case "$kind" in
        leader|worker) printf '%s' "${w%%/*}" ;;
        *)             printf '' ;;
    esac
}

# role: worker만 의미있음 (<issue_id>/server → server)
orch_wid_role() {
    local w="$1" kind
    kind="$(orch_wid_kind "$w")"
    case "$kind" in
        worker) printf '%s' "${w##*/}" ;;
        *)      printf '' ;;
    esac
}

orch_is_valid_worker_id() {
    [ "$(orch_wid_kind "$1")" != "invalid" ]
}

# 자기 worker_id 확인. 우선순위:
#   1) $ORCH_WORKER_ID (신규 표준)
#   2) $LOL_WORKER_ID  (후방호환 — 기존 워커 세션)
#   3) registry pane_id 역검색
# v1의 cwd 추론은 버그 원인이라 제거.
orch_detect_self() {
    local env_wid="${ORCH_WORKER_ID:-${LOL_WORKER_ID:-}}"
    if [ -n "$env_wid" ] && orch_is_valid_worker_id "$env_wid"; then
        printf '%s' "$env_wid"
        return 0
    fi
    [ -n "${TMUX_PANE:-}" ] || return 1
    local f wid
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        if [ "$(jq -r '.pane_id // ""' "$f" 2>/dev/null)" = "$TMUX_PANE" ]; then
            wid="$(jq -r '.worker_id // ""' "$f" 2>/dev/null)"
            [ -n "$wid" ] && { printf '%s' "$wid"; return 0; }
        fi
    done < <(find "$ORCH_ROOT" -path "*/workers/*.json" 2>/dev/null)
    return 1
}

# 이슈 ID 정규화 — 사용자 입력을 leader_id 로 sanitize.
# 정책: orch_id_safe 통과한 입력은 그대로 통과 (대소문자 보존). 트래커별 예:
#   Linear: MP-13       → MP-13
#   Jira:   PROJ-456    → PROJ-456
#   GitHub: 142         → 142
#   GitLab: my-issue#42 → my-issue#42   (# 등 자연 키 허용)
#   기타:   issue_42-rc → issue_42-rc
# 거부: 'orch' reserved / 빈 / 공백·제어문자 / shell metacharacters /
#       redirect·grouping·quoting / path traversal / slash (worker_id delimiter).
# fetch 실패 (트래커에 해당 이슈 없음) 는 여기서 막지 않음 — leader 가 fuzzy fallback 처리.
orch_normalize_issue_id() {
    local v="$1"
    orch_id_safe "$v" || return 1
    printf '%s' "$v"
}

# 입력 worker_id 가 registry 의 어떤 worker_id 와 case-insensitive 매칭되면 그 case 로 정규화.
# 매칭 없으면 입력 그대로. 'orch' 는 그대로.
#
# 0.13.0 부터 case 보존 정책이라 'MP-75' 와 'mp-75' 가 정규식 양쪽 다 통과하지만,
# inbox path / scope dir 가 exact case 라서 송신 시 두 표기를 혼용하면 다른 leader 로
# 인식돼 'WARN: 워커 등록 안 됨' 노이즈 + 메시지 미수신. 이 함수가 호출자 측에서 한 번
# 흡수해 등록 case 로 맞춰준다 (PAD-60 대응).
orch_resolve_worker_id_case() {
    local input="$1"
    [ -n "$input" ] || return 1
    [ "$input" = "orch" ] && { printf 'orch'; return 0; }
    local lower_input
    lower_input="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"
    local f wid lower_wid
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        wid="$(jq -r '.worker_id // ""' "$f" 2>/dev/null)"
        [ -n "$wid" ] || continue
        lower_wid="$(printf '%s' "$wid" | tr '[:upper:]' '[:lower:]')"
        if [ "$lower_wid" = "$lower_input" ]; then
            printf '%s' "$wid"
            return 0
        fi
    done < <(find "$ORCH_ROOT" -path "*/workers/*.json" 2>/dev/null)
    printf '%s' "$input"
}

# ─── 경로 헬퍼 (scope-aware) ──────────────────────────────────────────

orch_inbox_path() {
    local w="$1" kind scope
    kind="$(orch_wid_kind "$w" 2>/dev/null || true)"
    case "$kind" in
        orch|leader)
            printf '%s/%s.md' "$ORCH_INBOX" "$w" ;;
        worker)
            scope="$(orch_scope_dir "${w%%/*}")" || return 1
            printf '%s/inbox/%s.md' "$scope" "${w##*/}" ;;
        *) return 1 ;;
    esac
}

orch_archive_path() {
    local w="$1" kind scope
    kind="$(orch_wid_kind "$w" 2>/dev/null || true)"
    case "$kind" in
        orch)
            # orch 는 어느 MP 와도 안 묶이므로 top-level 보존
            printf '%s/%s-%s.md' "$ORCH_ARCHIVE" "$w" "$(date +%Y-%m-%d)" ;;
        leader)
            # leader 메시지 archive 는 자기 scope dir 안에 — issue-down 이 scope 째 archive
            scope="$(orch_scope_dir "$w")" || return 1
            printf '%s/leader-archive.md' "$scope" ;;
        worker)
            scope="$(orch_scope_dir "${w%%/*}")" || return 1
            printf '%s/archive/%s-%s.md' "$scope" "${w##*/}" "$(date +%Y-%m-%d)" ;;
        *) return 1 ;;
    esac
}

orch_worker_path() {
    local w="$1" kind scope
    kind="$(orch_wid_kind "$w" 2>/dev/null || true)"
    case "$kind" in
        orch|leader)
            printf '%s/%s.json' "$ORCH_WORKERS" "$w" ;;
        worker)
            scope="$(orch_scope_dir "${w%%/*}")" || return 1
            printf '%s/workers/%s.json' "$scope" "${w##*/}" ;;
        *) return 1 ;;
    esac
}

# scope 디렉토리 (<issue_id> sandbox 전체).
# `.orch/runs/<scope>/` 가 기본 위치. 평탄 `.orch/<scope>/` 도 fallback 으로 인식.
# 결정 순서:
#   1) runs/<scope> 디렉토리 존재 → runs path
#   2) 평탄 <scope> 디렉토리 존재 → 평탄 path (legacy)
#   3) 둘 다 없음 → runs path (issue-up 이 mkdir 할 위치)
orch_scope_dir() {
    local s="$1"
    [ "$s" = "orch" ] && return 1
    orch_id_safe "$s" || return 1
    local new_path="$ORCH_RUNS_DIR/$s"
    if [ -d "$new_path" ]; then
        printf '%s' "$new_path"; return 0
    fi
    local legacy_path="$ORCH_ROOT/$s"
    if [ -d "$legacy_path" ]; then
        printf '%s' "$legacy_path"; return 0
    fi
    printf '%s' "$new_path"
}

orch_scope_worktrees_dir() {
    local s="$1"
    local scope
    scope="$(orch_scope_dir "$s")" || return 1
    printf '%s/worktrees' "$scope"
}

# 종료된 leader 의 top-level inbox 파일 + lock 정리.
# 워커 inbox 는 scope_dir/inbox/<role>.md 라 scope archive 와 함께 보존 — 호출 noop.
# orch_worker_unregister 직후 호출하면 라우팅이 차단된 후라 race 없음.
orch_inbox_cleanup() {
    local wid="$1"
    local path
    path="$(orch_inbox_path "$wid" 2>/dev/null || true)"
    [ -n "$path" ] || return 0
    # 워커 inbox 는 scope_dir 안이라 issue-down 의 scope archive 가 이미 처리. 손대지 않음.
    case "$path" in
        "${ORCH_INBOX}/"*) rm -f "$path" "${path}.lock" ;;
    esac
}

# ─── settings.json 로더 (jq 의존) ─────────────────────────────────────

orch_settings_exists() {
    [ -f "$ORCH_SETTINGS" ]
}

orch_settings_require() {
    if ! orch_settings_exists; then
        echo "ERROR: $ORCH_SETTINGS 없음 — 먼저 /orch:setup 으로 생성하세요" >&2
        return 1
    fi
}

# 프로젝트 alias 목록
orch_settings_projects() {
    orch_settings_require || return 1
    jq -r '.projects | keys[]' "$ORCH_SETTINGS"
}

# 프로젝트 단일 필드 (path, kind, description, tech_stack)
orch_settings_project_field() {
    local project="$1" field="$2"
    orch_settings_require || return 1
    jq -r --arg p "$project" --arg f "$field" '
        if .projects[$p] == null then ""
        elif .projects[$p][$f] == null then ""
        elif (.projects[$p][$f] | type) == "array" then .projects[$p][$f] | join(", ")
        else .projects[$p][$f] | tostring end
    ' "$ORCH_SETTINGS"
}

orch_settings_global() {
    local field="$1"
    orch_settings_require || return 1
    jq -r --arg f "$field" '.[$f] // ""' "$ORCH_SETTINGS"
}

# 이슈 트래커 — linear | jira | github | gitlab | none.
# 필드 누락 시 'linear' (legacy 0.3.x 이하 워크스페이스 backwards-compat — 그때는 항상 Linear).
# 잘못된 값도 'linear' 로 폴백 (안전한 기본).
orch_settings_issue_tracker() {
    orch_settings_require || { printf 'linear'; return 1; }
    local v
    v="$(jq -r '.issue_tracker // "linear"' "$ORCH_SETTINGS")"
    case "$v" in
        linear|jira|github|gitlab|none) printf '%s' "$v" ;;
        *) printf 'linear' ;;
    esac
}

# git 호스트 — github | gitlab | none. 누락 시 'none'.
# 후속 라이프사이클 (PR 자동화 / cleanup) 분기에서 사용.
orch_settings_git_host() {
    orch_settings_require || { printf 'none'; return 1; }
    local v
    v="$(jq -r '.git_host // "none"' "$ORCH_SETTINGS")"
    case "$v" in
        github|gitlab|none) printf '%s' "$v" ;;
        *) printf 'none' ;;
    esac
}

# github 모드에서만 의미. settings.github_issue_repo (예: "owner/repo"). 없으면 빈 문자열.
orch_settings_github_issue_repo() {
    orch_settings_require || return 1
    jq -r '.github_issue_repo // ""' "$ORCH_SETTINGS"
}

# ─── Git host CLI 추상화 ──────────────────────────────────────────────
# git_host (github | gitlab) 에 따라 gh / glab CLI 명령을 분기. 호출자 (script / SKILL)
# 는 host 신경 안 쓰고 본 절의 헬퍼만 호출. 새 host 추가 시 본 절만 보강.

# host 별 필수 CLI 가용성 검증. github→gh / gitlab→glab. host 누락이면 실패.
# 호출 예: orch_require_git_host_cli || exit 2
orch_require_git_host_cli() {
    case "$(orch_settings_git_host)" in
        github) command -v gh   >/dev/null 2>&1 || { echo "ERROR: gh CLI 필요"   >&2; return 2; } ;;
        gitlab) command -v glab >/dev/null 2>&1 || { echo "ERROR: glab CLI 필요" >&2; return 2; } ;;
        *)      echo "ERROR: settings.json 의 git_host 가 github|gitlab 이어야 함" >&2; return 2 ;;
    esac
}

# PR (github) / MR (gitlab) state 조회 후 정규화. 출력:
#   merged | closed | open | unknown | '' (조회 실패 또는 state 비어 있음).
# 사용 예: state="$(orch_pr_state "$pr" [project_path])"
orch_pr_state() {
    local pr="$1" project_path="${2:-.}" host raw
    [ -n "$pr" ] || return 2
    host="$(orch_settings_git_host)"
    case "$host" in
        github)
            command -v gh >/dev/null 2>&1 || return 2
            raw="$(cd "$project_path" 2>/dev/null && gh pr view "$pr" --json state -q .state 2>/dev/null || true)"
            ;;
        gitlab)
            command -v glab >/dev/null 2>&1 || return 2
            # glab mr view 는 --output json 옵션이 없음 (glab 1.36+). REST API 직접 호출.
            raw="$(cd "$project_path" 2>/dev/null && glab api "projects/:fullpath/merge_requests/$pr" 2>/dev/null | jq -r '.state // ""' 2>/dev/null || true)"
            ;;
        *) return 2 ;;
    esac
    case "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')" in
        merged)        printf 'merged' ;;
        closed|locked) printf 'closed' ;;
        open|opened)   printf 'open'   ;;
        '')            printf ''       ;;
        *)             printf 'unknown' ;;
    esac
}

# 브랜치 이름으로 merged PR/MR 존재 여부. 0=merged, 1=not, 2=CLI 부재 또는 host 모름.
# 사용 예: orch_pr_merged_by_branch "$branch" "$project_path"
orch_pr_merged_by_branch() {
    local branch="$1" project_path="${2:-.}" host count
    [ -n "$branch" ] || return 2
    host="$(orch_settings_git_host)"
    case "$host" in
        github)
            command -v gh >/dev/null 2>&1 || return 2
            count="$(cd "$project_path" 2>/dev/null && gh pr list --state merged --head "$branch" --limit 1 --json number --jq 'length' 2>/dev/null || true)"
            ;;
        gitlab)
            command -v glab >/dev/null 2>&1 || return 2
            # glab mr list 는 --state / --output json 옵션이 없음 (glab 1.36+). REST API 직접 호출.
            # branch 에 #, +, @, . 등 자연 키가 포함될 수 있으므로 URL-encode 필수
            # (issue-id sanitize 가 이런 문자를 허용해 leader-spawn 의 branch_name 에 들어감).
            # jq @uri 로 인코딩, jq 부재 시 raw fallback (host CLI 자체가 jq 의존).
            local encoded_branch
            encoded_branch="$(printf '%s' "$branch" | jq -sRr @uri 2>/dev/null || printf '%s' "$branch")"
            count="$(cd "$project_path" 2>/dev/null && glab api "projects/:fullpath/merge_requests?state=merged&source_branch=$encoded_branch&per_page=1" 2>/dev/null | jq 'length' 2>/dev/null || true)"
            ;;
        *) return 2 ;;
    esac
    [ "${count:-0}" -gt 0 ]
}

orch_settings_project_exists() {
    local project="$1"
    orch_settings_exists || return 1
    [ "$(jq -r --arg p "$project" '.projects[$p] // empty' "$ORCH_SETTINGS")" != "" ]
}

# 프로젝트의 기본 브랜치 결정 — projects.<alias>.default_base_branch 만 사용. 누락이면 "develop".
# 모든 워크스페이스가 develop 플로우는 아니다 (예: lol-db-schema 는 main). 프로젝트별 값이
# 핵심 안전장치 — 0.12.0 이전엔 root .default_base_branch 가 폴백이었지만 프로젝트별 키만
# 의미있다는 결정에 따라 제거. 누락 시 leader-spawn 이 origin/develop fetch 에서 silently
# fail 한 뒤 worktree add 가 'fatal: invalid reference: origin/develop' 로 죽는 것을 알리기 위해
# 마지막 폴백은 'develop' 그대로.
orch_settings_project_base_branch() {
    local project="$1"
    orch_settings_require || return 1
    local override
    override="$(orch_settings_project_field "$project" default_base_branch 2>/dev/null || true)"
    if [ -n "$override" ]; then
        printf '%s' "$override"
        return 0
    fi
    printf 'develop'
}

# ─── Worker registry ──────────────────────────────────────────────────

# 인자: worker_id, kind, window_id, pane_id, cwd, [project_alias]
# project_alias 는 worker (특히 PM — worker_id=<issue>/pm) 의 worktree 가 어느 settings.projects
# 키 아래에 만들어졌는지 명시 보존용. 없으면 null. orch_cleanup_merged_worktrees 가 이 필드를
# 우선 참고하고, 없으면 worker_id 의 role 토큰 (예: 'server') 을 alias 로 가정한다 (구버전 호환).
#
# JSON 본문은 jq -n --arg 로 생성 — cwd 등 입력에 따옴표·백슬래시가 섞여 있어도 자동 escape.
orch_worker_register() {
    local wid="$1" kind="$2" window_id="$3" pane_id="$4" cwd="$5" project="${6:-}"
    local path scope started
    path="$(orch_worker_path "$wid")" || return 1
    mkdir -p "$(dirname "$path")"
    scope="$(orch_wid_scope "$wid")"
    if [ -z "$scope" ] || [ "$scope" = "$wid" ]; then
        scope=""
    fi
    started="$(date -Iseconds)"
    jq -n \
        --arg wid "$wid" \
        --arg kind "$kind" \
        --arg scope "$scope" \
        --arg window_id "$window_id" \
        --arg pane_id "$pane_id" \
        --arg cwd "$cwd" \
        --arg project "$project" \
        --arg started "$started" \
        '{
            worker_id: $wid,
            kind: $kind,
            scope: (if $scope == "" then null else $scope end),
            window_id: $window_id,
            pane_id: $pane_id,
            cwd: $cwd,
            project: (if $project == "" then null else $project end),
            started_at: $started
        }' >"$path"
}

orch_worker_field() {
    local wid="$1" field="$2" path kind scope_dir
    path="$(orch_worker_path "$wid")" || return 1
    if [ ! -f "$path" ]; then
        # 워커가 self-shutdown 으로 workers-archive 로 이동된 경우 폴백 — read-only 라 안전.
        kind="$(orch_wid_kind "$wid" 2>/dev/null || true)"
        if [ "$kind" = "worker" ]; then
            scope_dir="$(orch_scope_dir "${wid%%/*}")" || return 1
            path="$scope_dir/workers-archive/${wid##*/}.json"
            [ -f "$path" ] || return 1
        else
            return 1
        fi
    fi
    jq -r --arg f "$field" '.[$f] // empty' "$path"
}

orch_worker_unregister() {
    local wid="$1" path
    path="$(orch_worker_path "$wid")" || return 0
    rm -f "$path"
}

# 워커 종료 시 registry 를 지우지 않고 <scope>/workers-archive/<role>.json 으로 mv +
# terminated_at 필드 추가. report.sh 가 sidecar(jsonl) 분석할 때 cwd/started_at 이
# 필요하므로 종료 후에도 보존해야 한다. issue-down archive mv 시 디렉토리 통째로 이동.
# leader/orch 에는 의미 없음 (top-level 등록 — scope 디렉토리 아님). worker 만 처리.
orch_worker_archive_local() {
    local wid="$1" path archive_dir archive_path scope role scope_dir ts
    [ "$(orch_wid_kind "$wid")" = "worker" ] || { orch_worker_unregister "$wid"; return; }

    path="$(orch_worker_path "$wid")" || return 0
    [ -f "$path" ] || return 0

    scope="$(orch_wid_scope "$wid")"
    role="$(orch_wid_role "$wid")"
    scope_dir="$(orch_scope_dir "$scope")" || { rm -f "$path"; return 0; }

    archive_dir="$scope_dir/workers-archive"
    mkdir -p "$archive_dir"
    archive_path="$archive_dir/$role.json"
    ts="$(date -Iseconds)"

    if command -v jq >/dev/null 2>&1 \
        && jq --arg t "$ts" '. + {terminated_at: $t}' "$path" >"$archive_path" 2>/dev/null; then
        rm -f "$path"
    else
        mv "$path" "$archive_path" 2>/dev/null || rm -f "$path"
    fi
}

orch_worker_exists() {
    local wid="$1" path
    path="$(orch_worker_path "$wid")" || return 1
    [ -f "$path" ]
}

# 살아있는 leader 목록 — workers/ 의 모든 *.json 중 'orch.json' 만 제외 (예약 PM 식별자).
# 0.13.0 이전엔 'mp-*.json' glob 이었지만 issue_id 가 자유 형식이 된 후 generic 화.
orch_active_leaders() {
    [ -d "$ORCH_WORKERS" ] || return 0
    local f name
    for f in "$ORCH_WORKERS"/*.json; do
        [ -f "$f" ] || continue
        name="$(basename "$f" .json)"
        [ "$name" = "orch" ] && continue
        printf '%s\n' "$name"
    done
}

# 특정 leader 산하 worker_id 목록 (<issue_id>/role 형식)
orch_active_sub_workers() {
    local scope="$1"
    local scope_dir
    scope_dir="$(orch_scope_dir "$scope")" || return 0
    local dir="$scope_dir/workers"
    [ -d "$dir" ] || return 0
    local f
    for f in "$dir"/*.json; do
        [ -f "$f" ] || continue
        printf '%s/%s\n' "$scope" "$(basename "$f" .json)"
    done
}

# 살아있거나 self-shutdown 으로 종료된 워커 모두 (workers/ + workers-archive/).
# 같은 role 이 양쪽에 있으면 active 만 채택 (terminated → restarted 케이스).
# cleanup 처럼 라이프사이클 무관하게 워커가 *건드린* worktree 를 모두 잡아야 할 때 사용.
orch_all_sub_workers() {
    local scope="$1"
    local scope_dir
    scope_dir="$(orch_scope_dir "$scope")" || return 0
    local f dir role
    declare -A seen=()
    for dir in "$scope_dir/workers" "$scope_dir/workers-archive"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*.json; do
            [ -f "$f" ] || continue
            role="$(basename "$f" .json)"
            [ -n "${seen[$role]+x}" ] && continue
            seen[$role]=1
            printf '%s/%s\n' "$scope" "$role"
        done
    done
}

orch_pane_alive() {
    local pane_id="$1"
    [ -n "$pane_id" ] || return 1
    tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane_id"
}

# Claude Code TUI 프롬프트가 빈 상태인지 휴리스틱 판정.
# 인자: capture-pane stdout (멀티라인 문자열).
# 반환: 0=idle, 1=busy. 패턴 못 찾으면 0 (fail-open — 현재 동작 호환).
# TUI 형태: '│ > <content> │' (box-drawing) 또는 '> <content>' (단순). '>' 이후 본문이
# 공백·커서 글자뿐이면 idle, 본문이 있으면 busy.
_orch_capture_is_idle() {
    local cap="$1"
    [ -n "$cap" ] || return 0
    local prompt_line
    prompt_line="$(printf '%s\n' "$cap" | tail -n5 \
        | grep -E '(^|│|\|)[[:space:]]*>[[:space:]]' | tail -n1)"
    [ -n "$prompt_line" ] || return 0
    local after
    after="${prompt_line#*>}"
    after="${after%%│*}"
    after="${after%%|*}"
    after="$(printf '%s' "$after" | tr -d ' ▎▏▕_│|\t')"
    [ -z "$after" ]
}

# pane 의 마지막 영역을 capture 해 사용자 입력 중인지 판정.
# 반환: 0=idle, 1=busy. capture 실패 / pane_id 없음 / 휴리스틱 미매치는 idle (fail-open).
orch_pane_idle() {
    local pane_id="$1"
    [ -n "$pane_id" ] || return 0
    local cap
    cap="$(tmux capture-pane -p -t "$pane_id" -S -10 2>/dev/null)" || return 0
    _orch_capture_is_idle "$cap"
}

# ─── tmux pane 조작 ───────────────────────────────────────────────────

# 현재 pane이 속한 윈도우에 split. 출력: "<window_id> <pane_id>"
orch_split_in_current_window() {
    local cwd="$1"
    [ -n "${TMUX_PANE:-}" ] || { echo "ERROR: tmux 안에서 실행해야 합니다 (TMUX_PANE 미설정)" >&2; return 1; }
    local target_window pane_id window_id
    target_window="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}')"
    pane_id="$(tmux split-window -t "$target_window" -P -F '#{pane_id}' -c "$cwd")"
    window_id="$(tmux display-message -p -t "$pane_id" '#{window_id}')"
    tmux select-layout -t "$target_window" tiled >/dev/null 2>&1
    printf '%s %s' "$window_id" "$pane_id"
}

# 새 윈도우 생성. 출력: "<window_id> <pane_id>"
orch_new_window() {
    local name="$1" cwd="$2"
    local pane_id window_id
    pane_id="$(tmux new-window -d -t "$ORCH_TMUX_SESSION" -n "$name" -c "$cwd" -P -F '#{pane_id}')"
    window_id="$(tmux display-message -p -t "$pane_id" '#{window_id}')"
    printf '%s %s' "$window_id" "$pane_id"
}

# 기존 윈도우에 split. 출력: pane_id
orch_split_in_window() {
    local window_id="$1" cwd="$2"
    local pane_id
    pane_id="$(tmux split-window -t "$window_id" -P -F '#{pane_id}' -c "$cwd")"
    tmux select-layout -t "$window_id" tiled >/dev/null 2>&1
    printf '%s' "$pane_id"
}

# ─── 메시지 / 라우팅 ──────────────────────────────────────────────────

orch_gen_msg_id() {
    printf '%d-%s' "$(date +%s)" "$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c 6)"
}

# inbox에 메시지 append (flock 보호). 출력: msg_id
orch_append_message() {
    local from="$1" to="$2" body="$3"
    local id ts target
    id="$(orch_gen_msg_id)"
    ts="$(date -Iseconds)"
    target="$(orch_inbox_path "$to")" || return 1
    mkdir -p "$(dirname "$target")"
    {
        flock -x 9
        printf '\n---\nfrom: %s\nto: %s\nts: %s\nid: %s\n---\n%s\n' \
            "$from" "$to" "$ts" "$id" "$body" >>"$target"
    } 9>"${target}.lock"
    printf '%s' "$id"
}

# 2-tier 라우팅 정책 검사. OK=0, 차단=1.
orch_route_check() {
    local from="$1" to="$2"
    if [ "$from" = "$to" ]; then
        echo "ERROR: '$from' 가 자기 자신에게 보낼 수 없음" >&2
        return 1
    fi
    local fk tk fs ts
    fk="$(orch_wid_kind "$from")"
    tk="$(orch_wid_kind "$to")"
    fs="$(orch_wid_scope "$from")"
    ts="$(orch_wid_scope "$to")"

    if [ "$fk" = "invalid" ]; then
        echo "ERROR: 보낸이 worker_id 형식 오류: '$from'" >&2; return 1
    fi
    if [ "$tk" = "invalid" ]; then
        echo "ERROR: 받는이 worker_id 형식 오류: '$to'" >&2; return 1
    fi

    case "${fk} ${tk}" in
        "orch leader"|"leader orch")
            return 0 ;;
        "leader worker")
            [ "$fs" = "$ts" ] && return 0
            echo "ERROR: cross-issue 통신 차단 ('$from' → '$to')" >&2; return 1 ;;
        "worker leader")
            [ "$fs" = "$ts" ] && return 0
            echo "ERROR: 다른 MP의 leader에 직접 송신 차단 ('$from' → '$to')" >&2; return 1 ;;
        "leader leader")
            echo "ERROR: cross-issue 통신 차단 — leader끼리 직접 송신 안 됨 ('$from' → '$to')" >&2
            return 1 ;;
        "worker worker")
            echo "ERROR: 워커끼리 직접 송신 차단 — leader('$fs') 경유 필요" >&2
            return 1 ;;
        "worker orch")
            echo "ERROR: 워커는 orch에 직접 보낼 수 없음 — leader('$fs') 경유 필요" >&2
            return 1 ;;
        "orch worker")
            echo "ERROR: orch는 워커에 직접 송신 불가 — leader('$ts') 에 위임" >&2
            return 1 ;;
        *)
            echo "ERROR: 알 수 없는 라우팅 ($fk → $tk)" >&2; return 1 ;;
    esac
}

# 타겟 worker pane에 /orch:check-inbox <msg_id> 알림 (단건 본문 모드 직진입)
# 인자: to=worker_id, msg_id=방금 append 된 메시지 id (옵셔널 — 없으면 요약 모드 fallback)
orch_notify() {
    local to="$1"
    local msg_id="${2:-}"
    if ! tmux has-session -t "$ORCH_TMUX_SESSION" 2>/dev/null; then
        echo "WARN: tmux 세션 '$ORCH_TMUX_SESSION' 없음 — 메시지는 inbox에 저장됐지만 실시간 알림 못 함" >&2
        return 0
    fi
    local pane_id
    pane_id="$(orch_worker_field "$to" pane_id 2>/dev/null || true)"
    if [ -z "$pane_id" ]; then
        echo "WARN: '$to' 워커가 등록 안 됨 — 메시지는 inbox에 저장됐지만 받을 사람 없음" >&2
        return 0
    fi
    if ! orch_pane_alive "$pane_id"; then
        echo "WARN: '$to' 워커의 pane($pane_id)이 죽었음 — registry 정리 후 메시지만 보존" >&2
        orch_worker_unregister "$to"
        return 0
    fi
    local cmd='/orch:check-inbox'
    [ -n "$msg_id" ] && cmd="${cmd} ${msg_id}"

    # orch 타겟 입력 보호 가드: 사용자가 orch pane 에 타이핑 중이면 send-keys 가 버퍼를
    # 깨뜨림. 휴리스틱으로 busy 면 bg 에서 idle 까지 대기 후 송신. ORCH_NO_NOTIFY_GUARD=1
    # 로 비활성화 가능 (휴리스틱이 TUI 변경에 깨지면 escape hatch).
    if [ "$to" = "orch" ] && [ "${ORCH_NO_NOTIFY_GUARD:-0}" != "1" ] \
        && ! orch_pane_idle "$pane_id"; then
        (
            # 최대 20초 (1s × 20) 대기. idle 감지 즉시 송신. 타임아웃 도달하면 그래도
            # 송신 (notify 누락 < 입력 깨짐 위험을 일시 허용).
            attempts=0
            while [ "$attempts" -lt 20 ]; do
                sleep 1
                orch_pane_idle "$pane_id" && break
                attempts=$((attempts + 1))
            done
            orch_send_keys_line "$pane_id" "$cmd" >/dev/null 2>&1 || true
        ) </dev/null >/dev/null 2>&1 &
        disown 2>/dev/null || true
        return 0
    fi

    orch_send_keys_line "$pane_id" "$cmd" \
        || echo "WARN: '$to' (pane=$pane_id) 에 ${cmd} 전달 실패" >&2
}

# pane 에 한 줄/multi-line 전송 (텍스트 + Enter). race / copy-mode 흡수 방지.
# 1) copy-mode 또는 status-line modal 이면 cancel — 없으면 노옵
# 2) 텍스트 송신 → sleep → 별도 호출로 Enter
# 3) Enter 가 첫 호출에 흡수되는 사례 보고 잦아서 두 단계 분리는 의도적
# 4) sleep 은 큰 first_msg paste 흡수 시간 + pane 부하 마진 (0.15 → 0.25)
# 반환: 0=텍스트·Enter 둘 다 성공, 1=둘 중 하나라도 실패
orch_send_keys_line() {
    local pane_id="$1" text="$2"
    [ -n "$pane_id" ] || return 1
    tmux send-keys -t "$pane_id" -X cancel 2>/dev/null || true
    sleep 0.1
    tmux send-keys -t "$pane_id" -- "$text" 2>/dev/null || return 1
    sleep 0.25
    tmux send-keys -t "$pane_id" Enter 2>/dev/null || return 1
    return 0
}

# ─── inbox 통계 ───────────────────────────────────────────────────────

orch_inbox_count() {
    local path n
    path="$(orch_inbox_path "$1" 2>/dev/null)" || { printf '0'; return; }
    if [ ! -s "$path" ]; then printf '0'; return; fi
    n="$(grep -c '^---$' "$path" 2>/dev/null || true)"
    printf '%d' "$(( n / 2 ))"
}

orch_inbox_mtime() {
    local path
    path="$(orch_inbox_path "$1" 2>/dev/null)" || { printf -- '-'; return; }
    if [ -s "$path" ]; then
        date -r "$path" '+%Y-%m-%d %H:%M:%S'
    else
        printf -- '-'
    fi
}

# ─── worktree cleanup ────────────────────────────────────────────────
# issue-down 시 산하 워커의 머지된 브랜치 worktree 만 자동 정리. 미머지·dirty 는 보존.

# orch_branch_merged <project_path> <branch> <base_branch>
# 머지 확인. host (github/gitlab) 의 merged PR/MR (squash/rebase 포함) → git merge commit
# 순으로 검사. 0=merged, 1=not. host CLI 가 없으면 git fallback 만 사용.
orch_branch_merged() {
    local project_path="$1" branch="$2" base="$3"
    [ -d "$project_path" ] || return 1

    if orch_pr_merged_by_branch "$branch" "$project_path"; then
        return 0
    fi

    git -C "$project_path" fetch origin "$base" --quiet 2>/dev/null || true
    if git -C "$project_path" branch -r --merged "origin/$base" 2>/dev/null \
        | sed 's/^[[:space:]*]*//' | grep -qx "origin/${branch}"; then
        return 0
    fi
    return 1
}

# orch_worktree_cleanup <project_path> <worktree_path> <branch> [merge_verified]
# merge_verified=0 (기본): dirty 면 보존, branch -d 로 unmerged 보호.
# merge_verified=1: 호출자가 PR 머지를 이미 확인 — 빌드 산출물 등 untracked 는 버리고
#   --force 로 worktree remove, squash-merge 인식 못 하는 -d 거부 시 -D 폴백.
#   (squash-merge 시 git 메타·로컬 브랜치 잔재 누적 방지.)
orch_worktree_cleanup() {
    local project_path="$1" worktree_path="$2" branch="$3" merge_verified="${4:-0}"

    if [ -d "$worktree_path" ]; then
        if [ "$merge_verified" -ne 1 ]; then
            local dirty
            dirty="$(git -C "$worktree_path" status --porcelain 2>/dev/null)"
            if [ -n "$dirty" ]; then
                echo "    WARN: $worktree_path 에 미커밋/미추적 변경 있음 — 보존" >&2
                return 1
            fi
        fi
        local rm_args=(worktree remove "$worktree_path")
        [ "$merge_verified" -eq 1 ] && rm_args=(worktree remove --force "$worktree_path")
        if ! git -C "$project_path" "${rm_args[@]}" 2>/dev/null; then
            echo "    WARN: worktree remove 실패: $worktree_path" >&2
            git -C "$project_path" worktree prune 2>/dev/null || true
            if [ -d "$worktree_path" ]; then
                return 1
            fi
        fi
    fi

    if git -C "$project_path" show-ref --verify --quiet "refs/heads/$branch"; then
        if ! git -C "$project_path" branch -d "$branch" 2>/dev/null; then
            if [ "$merge_verified" -eq 1 ]; then
                if git -C "$project_path" branch -D "$branch" 2>/dev/null; then
                    echo "    INFO: '$branch' squash-merge 인식 안 됨 — -D 폴백 (머지 확인됨)" >&2
                else
                    echo "    WARN: 로컬 브랜치 '$branch' 삭제 실패 — 수동 정리 필요" >&2
                    return 1
                fi
            else
                echo "    WARN: 로컬 브랜치 '$branch' 삭제 거부 (-d 가 unmerged 보호) — 보존" >&2
                return 1
            fi
        fi
    fi
    return 0
}

# orch_cleanup_merged_worktrees <issue_id>
# issue 산하 워커 worktree 들 중 base 에 머지된 것만 정리. stdout 에 한 줄씩 결과 출력.
orch_cleanup_merged_worktrees() {
    local mp_id="$1"  # 변수명은 호환성 위해 유지 (의미: issue_id, 예 MP-13/PROJ-456/142)

    if ! orch_settings_exists; then
        echo "  cleanup skip: settings.json 없음"
        return 0
    fi

    local sub_wid role project_alias worktree_path project_path branch project_base current_branch any=0
    local cleaned=0 kept=0 skipped=0 partial=0
    declare -A pulled_paths=()
    # workers-archive 도 포함 — 워커가 wait-merge 답신 후 self-shutdown 으로 archive 된 상태에서
    # leader 가 issue-down 호출 시 active 만 보면 0개라 cleanup 이 통째로 noop 이 된다 (PAD-44).
    for sub_wid in $(orch_all_sub_workers "$mp_id"); do
        any=1
        role="${sub_wid##*/}"
        # project alias 해석:
        # 1. registry 의 project 필드 우선 (leader-spawn/review-spawn 이 기록). PM (role=pm)
        #    이나 reviewer (role=review-<project>) 의 worktree 가 어느 settings.projects 키
        #    아래 만들어졌는지 정확히 알 수 있는 유일한 경로.
        # 2. 없으면 role 토큰을 alias 로 폴백 (구버전 호환 — dev 워커는 role==project alias).
        project_alias="$(orch_worker_field "$sub_wid" project 2>/dev/null || true)"
        if [ -z "$project_alias" ] || [ "$project_alias" = "null" ]; then
            project_alias="$role"
        fi
        worktree_path="$(orch_worker_field "$sub_wid" cwd 2>/dev/null || true)"
        if [ -z "$worktree_path" ] || [ ! -d "$worktree_path" ]; then
            echo "  cleanup skip $sub_wid: worktree 경로 없음"
            skipped=$((skipped + 1))
            continue
        fi

        project_path="$(orch_settings_project_field "$project_alias" path 2>/dev/null || true)"
        if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
            echo "  cleanup skip $sub_wid: settings.json 의 project '$project_alias' path 없음 (role='$role')"
            skipped=$((skipped + 1))
            continue
        fi

        # 프로젝트별 default_base_branch (없으면 'develop' 으로 폴백 — orch_settings_project_base_branch 책임).
        project_base="$(orch_settings_project_base_branch "$project_alias" 2>/dev/null || true)"
        [ -n "$project_base" ] || project_base="develop"

        # project_path 의 local <base> ref 갱신 (project당 1회). 현재 체크아웃이 base 면
        # pull --ff-only, 다른 브랜치에 있으면 fetch <base>:<base> 로 working tree 안
        # 건드리고 ref 만 ff. 어느 쪽이든 결과를 명시적으로 로깅.
        if [ -z "${pulled_paths[$project_path]+x}" ]; then
            current_branch="$(git -C "$project_path" symbolic-ref --short HEAD 2>/dev/null || true)"
            if [ "$current_branch" = "$project_base" ]; then
                if git -C "$project_path" pull --ff-only origin "$project_base" >/dev/null 2>&1; then
                    echo "  pull OK $project_path ($project_base — current checkout, working tree 갱신)"
                else
                    echo "  pull skip $project_path ($project_base — ff-only 불가: 로컬 분기 / dirty)"
                fi
            else
                if git -C "$project_path" fetch origin "${project_base}:${project_base}" >/dev/null 2>&1; then
                    echo "  fetch OK $project_path (origin/$project_base → local $project_base, 현재 $current_branch 안 건드림)"
                else
                    echo "  fetch skip $project_path ($project_base — local ref 가 origin 보다 앞서 있거나 분기)"
                fi
            fi
            pulled_paths[$project_path]=1
        fi

        branch="$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
            echo "  cleanup skip $sub_wid: 현재 브랜치 미상"
            skipped=$((skipped + 1))
            continue
        fi

        if orch_branch_merged "$project_path" "$branch" "$project_base"; then
            if orch_worktree_cleanup "$project_path" "$worktree_path" "$branch" 1; then
                echo "  cleanup OK $sub_wid: $branch → $project_base 머지 확인, worktree+local branch 정리"
                cleaned=$((cleaned + 1))
            else
                echo "  cleanup partial $sub_wid: 머지됐지만 정리 도중 일부 실패 (위 WARN)"
                partial=$((partial + 1))
            fi
        else
            echo "  cleanup keep $sub_wid: $branch 미머지 또는 검출 실패 — worktree 보존 ($worktree_path)"
            kept=$((kept + 1))
        fi
    done
    [ "$any" -eq 0 ] && echo "  cleanup: 산하 워커 등록 없음 — skip"

    # 루프 중 worktree remove 가 부분 실패한 경우라도, 방문한 project 마다 prune
    # 1회 실행해 dangling 메타 (gitdir points to non-existent location) 정리.
    local pruned_path
    for pruned_path in "${!pulled_paths[@]}"; do
        if git -C "$pruned_path" worktree prune 2>/dev/null; then
            echo "  prune OK $pruned_path"
        fi
    done

    # 외부에서 inbox 알림·로그에 사용 가능하도록 카운터 노출.
    ORCH_CLEANUP_SUMMARY_CLEANED="$cleaned"
    ORCH_CLEANUP_SUMMARY_KEPT="$kept"
    ORCH_CLEANUP_SUMMARY_PARTIAL="$partial"
    ORCH_CLEANUP_SUMMARY_SKIPPED="$skipped"
    echo "  cleanup summary: cleaned=$cleaned kept=$kept partial=$partial skipped=$skipped"
    return 0
}

# orch_orphan_cleanup_suggest <issue_id>
# leader registry 에서 leader 가 사라진 fallback 경로용. 자동 삭제 안 함 — settings 의 모든
# project 에 대해 (1) git worktree prune (메타데이터만 정리, 안전) 실행하고 (2) issue_id 토큰
# 과 일치하는 로컬 브랜치 후보를 PR 머지 상태와 함께 출력만 한다. 사용자가 결과를 보고
# 직접 git branch -D 실행하도록.
# (cascade 흐름이 깨져 leader 가 archive 만 mv 하고 죽었을 때 잔재 보강.)
orch_orphan_cleanup_suggest() {
    local issue_id="$1"
    [ -n "$issue_id" ] || return 0

    if ! orch_settings_exists; then
        echo "  orphan: settings.json 없음 — skip"
        return 0
    fi

    # issue_id 토큰 (예: MP-13, PROJ-456, 142, issue42). 브랜치 매칭은 대소문자 무시.
    local id_token="$issue_id"

    local project alias_path
    local suggestions=()
    for alias_path in $(orch_settings_projects 2>/dev/null); do
        project="$(orch_settings_project_field "$alias_path" path 2>/dev/null || true)"
        [ -z "$project" ] || [ ! -d "$project" ] && continue
        [ -d "$project/.git" ] || [ -f "$project/.git" ] || continue

        if git -C "$project" worktree prune 2>/dev/null; then
            echo "  orphan prune OK $project"
        fi

        # for-each-ref 의 '*' 는 / 를 넘지 못해 fix/PROJ-77 같은 브랜치를 못 잡는다.
        # 모든 ref 를 받아 grep 으로 패턴 매칭 (대소문자 무시, issue_id 토큰).
        local b base_branch
        base_branch="$(orch_settings_project_base_branch "$alias_path" 2>/dev/null || echo develop)"
        while IFS= read -r b; do
            [ -z "$b" ] && continue
            if orch_branch_merged "$project" "$b" "$base_branch"; then
                suggestions+=("git -C $project branch -D $b   # ${alias_path}: 머지 확인됨")
            else
                suggestions+=("# git -C $project branch -D $b   # ${alias_path}: 머지 미확인 — 직접 검토")
            fi
        done < <(git -C "$project" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null \
            | grep -i -E "(^|[/_-])${id_token}([/_-]|$)" || true)
    done

    if [ "${#suggestions[@]}" -gt 0 ]; then
        echo "  orphan 브랜치 후보 ($issue_id) — 검토 후 직접 실행:"
        printf '    %s\n' "${suggestions[@]}"
    else
        echo "  orphan: '$issue_id' 패턴 일치 브랜치 없음"
    fi
    return 0
}

# ─── 에러 로깅 ─────────────────────────────────────────────────────────
# 어느 스크립트든 실패하면 한 줄 JSON 으로 추적용 로그 남긴다.
# scope-aware: orch / unknown 은 top-level errors.jsonl,
# <issue_id>, <issue_id>/role 은 .orch/runs/<issue_id>/errors.jsonl (issue-down 이 scope 째 archive 함).

# orch_errors_log_path [<wid>] — 호출자 worker_id 기반 errors.jsonl 경로 결정.
# 인자 없으면 ORCH_WORKER_ID(또는 LOL_WORKER_ID 후방호환) → orch_detect_self 순으로 추론.
orch_errors_log_path() {
    local wid="${1:-}"
    [ -z "$wid" ] && wid="${ORCH_WORKER_ID:-${LOL_WORKER_ID:-}}"
    [ -z "$wid" ] && wid="$(orch_detect_self 2>/dev/null || true)"
    local scope scope_dir
    scope="$(orch_wid_scope "$wid" 2>/dev/null || true)"
    if [ -n "$scope" ]; then
        scope_dir="$(orch_scope_dir "$scope")" || { printf '%s/errors.jsonl' "$ORCH_ROOT"; return; }
        printf '%s/errors.jsonl' "$scope_dir"
    else
        printf '%s/errors.jsonl' "$ORCH_ROOT"
    fi
}

orch_log_error() {
    # 인자: <source-script> <exit_code> <stderr_text>
    local src="${1:-unknown}" rc="${2:-?}" stderr_text="${3:-}"
    local wid="${ORCH_WORKER_ID:-${LOL_WORKER_ID:-}}"
    [ -z "$wid" ] && wid="$(orch_detect_self 2>/dev/null || true)"
    [ -z "$wid" ] && wid="unknown"

    local log_path
    log_path="$(orch_errors_log_path "$wid")"
    mkdir -p "$(dirname "$log_path")" 2>/dev/null || true
    local ts
    ts="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"

    # stderr 너무 길면 자르고 (8KB), null 바이트 제거
    stderr_text="$(printf '%s' "$stderr_text" | tr -d '\0' | tail -c 8192)"

    if command -v jq >/dev/null 2>&1; then
        jq -nc \
            --arg ts "$ts" \
            --arg wid "$wid" \
            --arg src "$src" \
            --arg rc "$rc" \
            --arg err "$stderr_text" \
            '{ts:$ts, worker_id:$wid, script:$src, exit_code:($rc|tonumber? // $rc), stderr:$err}' \
            >> "$log_path" 2>/dev/null || true
    else
        local esc_err
        esc_err="$(printf '%s' "$stderr_text" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')"
        printf '{"ts":"%s","worker_id":"%s","script":"%s","exit_code":%s,"stderr":"%s"}\n' \
            "$ts" "$wid" "$src" "$rc" "$esc_err" >> "$log_path" 2>/dev/null || true
    fi

    # Slack 알림 — 에러 발생 시. notify-slack.sh 자체가 무한루프 방지를 위해
    # ORCH_NOTIFY_ENABLED=0 또는 webhook 미설정 시 조용히 종료한다.
    local notify_dir notify_script
    notify_dir="$(dirname "${BASH_SOURCE[0]}")"
    notify_script="${notify_dir}/notify-slack.sh"
    if [ -x "$notify_script" ]; then
        local first_err scope
        first_err="$(printf '%s' "$stderr_text" | head -n1 | cut -c1-120)"
        scope="$(orch_wid_scope "$wid" 2>/dev/null || true)"
        "$notify_script" error "${scope:-${wid}}" "${src} rc=${rc}: ${first_err}" 2>/dev/null || true
    fi
}

# 모든 errors.jsonl 모으기 — top-level + 모든 scope dir 의 errors.jsonl (live + archive).
# stdout 으로 한 줄 JSON 들 출력. /orch:errors 가 사용.
# scope dir 후보: runs/<id>/ (기본), .orch/<id>/ (legacy 평탄), archive/<id>-YYYY-MM-DD/ (archived).
# .orch root 직속의 reserved 디렉토리 (inbox/archive/workers/runs) 는 제외.
orch_collect_all_errors() {
    [ -f "$ORCH_ERRORS_LOG" ] && cat "$ORCH_ERRORS_LOG" 2>/dev/null
    local f d name
    for f in "$ORCH_RUNS_DIR"/*/errors.jsonl; do
        [ -f "$f" ] && cat "$f" 2>/dev/null
    done
    for d in "$ORCH_ROOT"/*/; do
        [ -d "$d" ] || continue
        name="$(basename "${d%/}")"
        case "$name" in
            inbox|archive|workers|runs) continue ;;
        esac
        f="${d}errors.jsonl"
        [ -f "$f" ] && cat "$f" 2>/dev/null
    done
    for f in "$ORCH_ARCHIVE"/*/errors.jsonl; do
        [ -f "$f" ] && cat "$f" 2>/dev/null
    done
    return 0
}

# orch_install_error_trap — 호출한 스크립트의 비0 종료를 자동으로 errors.jsonl 에 기록.
# 사용: 스크립트 상단에 source lib.sh 직후 orch_install_error_trap "$0"
# stderr 를 임시 파일에 미러링한 뒤 EXIT 시 비0 이면 그 내용을 로그한다.
orch_install_error_trap() {
    local src="${1:-$0}"
    local src_base
    src_base="$(basename "$src" .sh)"
    local stderr_buf
    stderr_buf="$(mktemp -t "orch-stderr-${src_base}-XXXXXX")" || return 0
    export __ORCH_STDERR_BUF="$stderr_buf"
    export __ORCH_SRC="$src_base"
    # tee 로 원래 stderr 와 임시 파일에 동시 기록
    exec 2> >(tee -a "$stderr_buf" >&2)
    trap '__rc=$?
        if [ "$__rc" -ne 0 ] && [ -n "${__ORCH_STDERR_BUF:-}" ]; then
            orch_log_error "${__ORCH_SRC:-unknown}" "$__rc" "$(cat "$__ORCH_STDERR_BUF" 2>/dev/null || true)"
        fi
        [ -n "${__ORCH_STDERR_BUF:-}" ] && rm -f "$__ORCH_STDERR_BUF" 2>/dev/null
        exit $__rc' EXIT
}
