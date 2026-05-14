#!/usr/bin/env bash
# /orch:setup — settings.json 자동 추론 + 출력.
# base_dir 의 sibling 디렉토리를 스캔해 프로젝트 메타데이터 초안을 생성한다.
# 환경변수:
#   ORCH_PROJECT_GLOB   매칭 패턴 (기본: *)  예: "myorg-*"
#   ORCH_PROJECT_PREFIX alias 추출 시 제거할 prefix (기본: 없음 — dirname 그대로)
# 결과는 사용자가 직접 편집해 description / tech_stack 을 보강해야 한다.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="$ORCH_SCRIPTS_ROOT"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/core/lib.sh
source "${ORCH_SCRIPTS_ROOT}/core/lib.sh"

UPDATE_MODE=0
ISSUE_TRACKER=""
GITHUB_ISSUE_REPO=""
GIT_HOST=""
NOTIFY=""
USAGE='사용법: /orch:setup [--update]
                  [--issue-tracker linear|github|gitlab|none]
                  [--github-repo owner/repo|group/project]
                  [--git-host github|gitlab|none]
                  [--notify on|off]'
while [ "$#" -gt 0 ]; do
    case "$1" in
        --update) UPDATE_MODE=1 ;;
        --issue-tracker)
            shift
            ISSUE_TRACKER="${1:-}"
            case "$ISSUE_TRACKER" in
                linear|github|gitlab|none) ;;
                *) echo "ERROR: --issue-tracker 는 linear|github|gitlab|none ('$ISSUE_TRACKER')" >&2; exit 2 ;;
            esac
            ;;
        --issue-tracker=*)
            ISSUE_TRACKER="${1#--issue-tracker=}"
            case "$ISSUE_TRACKER" in
                linear|github|gitlab|none) ;;
                *) echo "ERROR: --issue-tracker 는 linear|github|gitlab|none ('$ISSUE_TRACKER')" >&2; exit 2 ;;
            esac
            ;;
        --github-repo)
            shift
            GITHUB_ISSUE_REPO="${1:-}"
            ;;
        --github-repo=*)
            GITHUB_ISSUE_REPO="${1#--github-repo=}"
            ;;
        --git-host)
            shift
            GIT_HOST="${1:-}"
            case "$GIT_HOST" in
                github|gitlab|none) ;;
                *) echo "ERROR: --git-host 는 github|gitlab|none ('$GIT_HOST')" >&2; exit 2 ;;
            esac
            ;;
        --git-host=*)
            GIT_HOST="${1#--git-host=}"
            case "$GIT_HOST" in
                github|gitlab|none) ;;
                *) echo "ERROR: --git-host 는 github|gitlab|none ('$GIT_HOST')" >&2; exit 2 ;;
            esac
            ;;
        --notify)
            shift
            NOTIFY="${1:-}"
            case "$NOTIFY" in
                on|off) ;;
                *) echo "ERROR: --notify 는 on|off ('$NOTIFY')" >&2; exit 2 ;;
            esac
            ;;
        --notify=*)
            NOTIFY="${1#--notify=}"
            case "$NOTIFY" in
                on|off) ;;
                *) echo "ERROR: --notify 는 on|off ('$NOTIFY')" >&2; exit 2 ;;
            esac
            ;;
        *) echo "$USAGE" >&2; exit 2 ;;
    esac
    shift
done

if [ "$ISSUE_TRACKER" = "github" ] && [ -z "$GITHUB_ISSUE_REPO" ]; then
    echo "ERROR: --issue-tracker github 는 --github-repo owner/repo 도 함께 필요" >&2
    exit 2
fi
if [ -n "$ISSUE_TRACKER" ] && [ "$ISSUE_TRACKER" != "github" ] && [ "$ISSUE_TRACKER" != "gitlab" ] && [ -n "$GITHUB_ISSUE_REPO" ]; then
    echo "WARN: --github-repo 는 --issue-tracker github|gitlab 일 때만 의미 있음 — 무시" >&2
    GITHUB_ISSUE_REPO=""
fi
if [ "$UPDATE_MODE" -eq 0 ] && [ -z "$ISSUE_TRACKER" ] && [ -n "$GITHUB_ISSUE_REPO" ]; then
    echo "WARN: --github-repo 는 --issue-tracker github|gitlab 과 함께 지정해야 의미 있음 — 무시" >&2
    GITHUB_ISSUE_REPO=""
fi

BASE_DIR="$(dirname "$ORCH_ROOT")"

if [ "$UPDATE_MODE" -eq 1 ] && ! orch_settings_exists; then
    echo "ERROR: $ORCH_SETTINGS 없음 — /orch:setup --update 는 기존 settings.json 이 있을 때만 사용합니다." >&2
    echo "  - 처음 셋업: /orch:setup" >&2
    echo "  - 다른 위치에서 실행 중이면 ORCH_ROOT=/abs/workspace/.orch 지정 후 재실행" >&2
    exit 2
fi

mkdir -p "$ORCH_ROOT" "$ORCH_INBOX" "$ORCH_ARCHIVE" "$ORCH_WORKERS" "$ORCH_RUNS_DIR"

if orch_settings_exists && [ "$UPDATE_MODE" -eq 0 ]; then
    echo "ERROR: $ORCH_SETTINGS 이미 존재합니다." >&2
    echo "  - 기존 값 보존하면서 새 프로젝트만 추가: /orch:setup --update" >&2
    echo "  - 완전히 재생성: 파일 삭제 후 다시 실행" >&2
    exit 2
fi

orch_install_error_trap "$0"

infer_project() {
    local dir="$1" alias="$2"
    local kind="" desc=""
    local -a tech_stack=()

    # ── tech_stack 추론 ────────────────────────────
    if [ -f "$dir/package.json" ]; then
        if grep -q '"next"' "$dir/package.json" 2>/dev/null; then tech_stack+=("Next.js"); fi
        if grep -q '"react"' "$dir/package.json" 2>/dev/null; then tech_stack+=("React"); fi
        if grep -q '"vue"' "$dir/package.json" 2>/dev/null; then tech_stack+=("Vue"); fi
        if [ -f "$dir/tsconfig.json" ]; then tech_stack+=("TypeScript"); fi
        if [ "${#tech_stack[@]}" -eq 0 ]; then tech_stack+=("Node.js"); fi
    fi
    if compgen -G "$dir/build.gradle*" >/dev/null 2>&1; then
        tech_stack+=("Java" "Gradle")
        if grep -qE 'spring-boot' "$dir"/build.gradle* 2>/dev/null; then
            tech_stack+=("Spring Boot")
        fi
    fi
    if [ -f "$dir/pom.xml" ]; then
        tech_stack+=("Java" "Maven")
        if grep -q 'spring-boot' "$dir/pom.xml" 2>/dev/null; then
            tech_stack+=("Spring Boot")
        fi
    fi
    if [ -f "$dir/Cargo.toml" ]; then tech_stack+=("Rust" "Cargo"); fi
    if [ -f "$dir/go.mod" ]; then tech_stack+=("Go"); fi

    # ── kind 휴리스틱 ──────────────────────────────
    local stack_blob=" ${tech_stack[*]+${tech_stack[*]}} "
    if [[ "$stack_blob" == *" Next.js "* ]] || [[ "$stack_blob" == *" React "* ]] || [[ "$stack_blob" == *" Vue "* ]]; then
        kind="frontend-spa"
    elif [[ "$stack_blob" == *" Spring Boot "* ]]; then
        kind="backend-api"
    elif [[ "$alias" == *repository* ]] || [[ "$alias" == *repo* ]] || [[ "$alias" == *lib* ]]; then
        kind="shared-library"
    else
        kind="unknown"
    fi

    # ── description (CLAUDE.md / README 첫 비어있지 않은 단락) ─
    # CR(\r) / LF / 들여쓰기 / 헤더 줄 제거 후 본문 2줄을 합친다.
    local cand
    for cand in CLAUDE.md README.md README; do
        if [ -f "$dir/$cand" ]; then
            desc="$(tr -d '\r' <"$dir/$cand" \
                | awk 'BEGIN{n=0} /^[#=>!\-`]/ {next} NF { sub(/^[ \t]+/, ""); print; n++; if (n>=2) exit }' \
                | head -c 200 | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')"
            [ -n "$desc" ] && break
        fi
    done
    [ -z "$desc" ] && desc="(설명 없음 — settings.json 직접 편집해 채워주세요)"

    local tech_json
    if [ "${#tech_stack[@]}" -eq 0 ]; then
        tech_json='[]'
    else
        tech_json="$(printf '%s\n' "${tech_stack[@]}" | jq -R . | jq -s .)"
    fi

    # 프로젝트별 기본 브랜치 자동 감지. 우선순위:
    #   1) git remote show origin 의 'HEAD branch' (네트워크 — 가장 정확).
    #   2) git symbolic-ref refs/remotes/origin/HEAD (로컬 캐시 — clone 시점 값이라 stale 가능).
    #   3) 흔한 후보 (develop / main / master) 중 origin 에 존재하는 것.
    # 사용자가 결과 미더우면 settings.json 직접 편집 가능.
    local base_branch=""
    if [ -d "$dir/.git" ] || git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
        base_branch="$(timeout 5 git -C "$dir" remote show origin 2>/dev/null \
            | awk '/HEAD branch:/ {print $NF; exit}')"
        if [ -z "$base_branch" ] || [ "$base_branch" = "(unknown)" ]; then
            base_branch="$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null \
                | sed 's@^origin/@@' || true)"
        fi
        if [ -z "$base_branch" ]; then
            local cand
            for cand in develop main master; do
                if git -C "$dir" rev-parse --verify --quiet "refs/remotes/origin/$cand" >/dev/null 2>&1; then
                    base_branch="$cand"
                    break
                fi
            done
        fi
    fi

    if [ -n "$base_branch" ]; then
        jq -n \
            --arg path "$dir" \
            --arg kind "$kind" \
            --arg desc "$desc" \
            --arg base "$base_branch" \
            --argjson tech "$tech_json" \
            '{path: $path, kind: $kind, tech_stack: $tech, default_base_branch: $base, description: $desc}'
    else
        jq -n \
            --arg path "$dir" \
            --arg kind "$kind" \
            --arg desc "$desc" \
            --argjson tech "$tech_json" \
            '{path: $path, kind: $kind, tech_stack: $tech, description: $desc}'
    fi
}

# 프로젝트 후보 — 환경변수 ORCH_PROJECT_GLOB 으로 패턴 지정 가능 (기본 *)
# *-worktrees / *-worktree / .orch / .* hidden 은 자동 제외.
project_glob="${ORCH_PROJECT_GLOB:-*}"
declare -a candidates=()
shopt -s nullglob
for d in "$BASE_DIR"/$project_glob/; do
    [ -d "$d" ] || continue
    name="$(basename "${d%/}")"
    case "$name" in
        .*|.orch) continue ;;  # hidden / orch root 제외
        *-worktrees|*-worktree) continue ;;  # worktree 잔재 제외
    esac
    candidates+=("${d%/}")
done
shopt -u nullglob

if [ "${#candidates[@]}" -eq 0 ]; then
    echo "ERROR: ${BASE_DIR}/${project_glob} 매칭 디렉토리 없음" >&2
    echo "  - ORCH_PROJECT_GLOB 환경변수로 다른 패턴 지정 가능 (예: ORCH_PROJECT_GLOB='myorg-*')" >&2
    exit 2
fi

# alias 추출 — ORCH_PROJECT_PREFIX 가 있으면 제거 후 사용, 없으면 dirname 그대로
project_prefix="${ORCH_PROJECT_PREFIX:-}"
projects_json="$(jq -n '{}')"
for d in "${candidates[@]}"; do
    name="$(basename "$d")"
    if [ -n "$project_prefix" ] && [[ "$name" == "${project_prefix}"* ]]; then
        alias="${name#${project_prefix}}"
    else
        alias="$name"
    fi
    # alias 가 비면 (= prefix 와 정확히 일치) dirname 그대로
    [ -z "$alias" ] && alias="$name"
    proj_json="$(infer_project "$d" "$alias")"
    projects_json="$(jq --arg a "$alias" --argjson p "$proj_json" '.[$a] = $p' <<<"$projects_json")"
done

tracker_for_init="${ISSUE_TRACKER:-none}"
git_host_for_init="${GIT_HOST:-none}"
# --notify 미지정 시 false (소음 없는 기본). on 만 명시적으로 true.
notify_for_init=false
[ "$NOTIFY" = "on" ] && notify_for_init=true

new_settings="$(jq -n \
    --arg base "$BASE_DIR" \
    --arg tracker "$tracker_for_init" \
    --arg gh_repo "$GITHUB_ISSUE_REPO" \
    --arg git_host "$git_host_for_init" \
    --argjson notify_enabled "$notify_for_init" \
    --argjson projects "$projects_json" \
    '{
        version: 1,
        base_dir: $base,
        issue_tracker: $tracker,
        git_host: $git_host,
        notify: { slack_enabled: $notify_enabled },
        projects: $projects
     }
     | if $gh_repo != "" then .github_issue_repo = $gh_repo else . end'
)"

# --update: 기존 값 보존, 새 프로젝트만 추가, 기존 프로젝트는 그대로.
# 단 default_base_branch 필드는 기존 프로젝트에도 누락 시 추론값으로 보강한다
# (override 가 이미 있으면 그대로 유지).
#
# 머지 정책 — alias 가 아니라 path 기준 매칭 (PAD-27):
#   ORCH_PROJECT_PREFIX 가 셋업 시점과 다르면 동일 디렉토리가 다른 alias 로 잡혀
#   $old 의 description/tech_stack/override 가 통째로 사라지는 사고가 있었음.
#   path 는 절대경로로 stable 식별자라 prefix/glob 변동에 강함.
if [ "$UPDATE_MODE" -eq 1 ] && orch_settings_exists; then
    # --notify 인자: on/off 명시면 override, 미지정이면 기존 값 유지. 빈 문자열을 빈 채로 jq 에 넘기고
    # 안에서 분기. (true/false 둘 다 받아야 하므로 --argjson 으로 boolean 직렬화.)
    notify_override="null"
    [ "$NOTIFY" = "on" ] && notify_override="true"
    [ "$NOTIFY" = "off" ] && notify_override="false"

    # 인자로 받은 ISSUE_TRACKER / GIT_HOST 가 있으면 override, 없으면 기존 값 유지
    new_settings="$(jq \
        --slurpfile cur "$ORCH_SETTINGS" \
        --arg tracker "$ISSUE_TRACKER" \
        --arg gh_repo "$GITHUB_ISSUE_REPO" \
        --arg git_host "$GIT_HOST" \
        --argjson notify_override "$notify_override" \
        '
        . as $new |
        ($cur[0] // {}) as $old |
        ( if $tracker != "" then $tracker
          # legacy file 에 issue_tracker 없으면 "linear" 로 명시 백필 (0.3.x 이하 = 항상 Linear).
          # 사용자가 fresh 셋업으로 '"'"'none'"'"' 을 명시적으로 골랐던 경우는 $old 에 그 값이 남아있음.
          else ($old.issue_tracker // "linear") end ) as $final_tracker |
        ( if $tracker == "github" or $tracker == "gitlab"
              or ($tracker == "" and ($final_tracker == "github" or $final_tracker == "gitlab"))
          then ( if $gh_repo != "" then $gh_repo
                 else ($old.github_issue_repo // "") end )
          else "" end ) as $final_gh_repo |
        ( if $git_host != "" then $git_host
          else ($old.git_host // "none") end ) as $final_git_host |
        ( if $notify_override != null then $notify_override
          else ($old.notify.slack_enabled // false) end ) as $final_notify_enabled |

        # ── projects 머지 (alias-by-path) ──
        # 1) old 를 path 로 인덱스. path 비어있는 entry 는 alias 그대로 가는 orphan 트랙.
        ([ $old.projects // {} | to_entries[]
           | select((.value.path // "") != "")
           | {key: .value.path, value: {alias: .key, value: .value}}
         ] | from_entries) as $old_by_path |

        # 2) new 순회: path 매치 있으면 old alias + old value (default_base_branch 보강만), 없으면 new 그대로.
        ([ $new.projects | to_entries[]
           | .key as $new_alias | .value as $new_v
           | ($new_v.path // "") as $p
           | ($old_by_path[$p] // null) as $hit
           | if $hit != null then
               $hit.value as $old_v
               | {
                   key: $hit.alias,
                   value: (
                     if ($old_v.default_base_branch // "") == "" and ($new_v.default_base_branch // "") != ""
                     then $old_v + {default_base_branch: $new_v.default_base_branch}
                     else $old_v
                     end
                   )
                 }
             else
               {key: $new_alias, value: $new_v}
             end
         ]) as $merged_new |

        # 3) new 에 매치 안 된 old entry (glob 좁아져 못 잡혔거나 path 비어있던 orphan) 보존.
        ([$merged_new[] | .key]) as $taken_aliases |
        ([ $old.projects // {} | to_entries[]
           | select(([.key] | inside($taken_aliases)) | not)
         ]) as $orphan_olds |

        ($old + {
          version: ($old.version // $new.version),
          base_dir: ($old.base_dir // $new.base_dir),
          issue_tracker: $final_tracker,
          git_host: $final_git_host,
          notify: ( ($old.notify // {}) + { slack_enabled: $final_notify_enabled } ),
          projects: (($merged_new + $orphan_olds) | from_entries)
        })
        | del(.default_base_branch)
        | if $final_gh_repo != "" then .github_issue_repo = $final_gh_repo else del(.github_issue_repo) end
    ' <<<"$new_settings")"
fi

printf '%s\n' "$new_settings" >"$ORCH_SETTINGS"

echo "OK: $ORCH_SETTINGS 작성 완료"
echo "── 추론된 내용 (직접 편집해 보강하세요) ──"
cat "$ORCH_SETTINGS"
echo "──────────────────────────────────────────"
final_tracker="$(jq -r '.issue_tracker // "none"' "$ORCH_SETTINGS")"
echo "다음 단계:"
echo "  1. 위 settings.json 의 description / tech_stack 손보세요"
echo "  2. /orch:validate-settings — settings.json 이 실제 프로젝트와 일치하는지 검증"
echo "  3. /orch:up 으로 orch pane 등록"
case "$final_tracker" in
    linear) echo "  4. /orch:issue-up <issue-id> (Linear 이슈 키 / 예: MP-13) 로 첫 leader 띄우기" ;;
    github) echo "  4. /orch:issue-up <issue-num> (GitHub Issue 번호) 로 첫 leader 띄우기" ;;
    gitlab) echo "  4. /orch:issue-up <issue-iid> (GitLab Issue IID) 로 첫 leader 띄우기" ;;
    *)      echo "  4. /orch:issue-up <num> 로 첫 leader 띄움 — leader 가 orch 에 spec 요청 (트래커 없음)" ;;
esac
echo
echo "TIP: 플러그인 자체 위생이 의심되면 /orch:validate-plugin (문법 + 종속어 검출)."
