#!/usr/bin/env bash
# /orch:setup — settings.json 자동 추론 + 출력.
# base_dir 의 sibling 디렉토리를 스캔해 프로젝트 메타데이터 초안을 생성한다.
# 환경변수:
#   ORCH_PROJECT_GLOB   매칭 패턴 (기본: *)  예: "myorg-*"
#   ORCH_PROJECT_PREFIX alias 추출 시 제거할 prefix (기본: 없음 — dirname 그대로)
# 결과는 사용자가 직접 편집해 description / tech_stack 을 보강해야 한다.

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

UPDATE_MODE=0
case "${1:-}" in
    --update) UPDATE_MODE=1 ;;
    "") ;;
    *) echo "사용법: /orch:setup [--update]" >&2; exit 2 ;;
esac

BASE_DIR="$(dirname "$ORCH_ROOT")"

mkdir -p "$ORCH_ROOT" "$ORCH_INBOX" "$ORCH_ARCHIVE" "$ORCH_WORKERS"

if orch_settings_exists && [ "$UPDATE_MODE" -eq 0 ]; then
    echo "ERROR: $ORCH_SETTINGS 이미 존재합니다." >&2
    echo "  - 기존 값 보존하면서 새 프로젝트만 추가: /orch:setup --update" >&2
    echo "  - 완전히 재생성: 파일 삭제 후 다시 실행" >&2
    exit 2
fi

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

    jq -n \
        --arg path "$dir" \
        --arg kind "$kind" \
        --arg desc "$desc" \
        --argjson tech "$tech_json" \
        '{path: $path, kind: $kind, tech_stack: $tech, description: $desc}'
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

new_settings="$(jq -n \
    --arg base "$BASE_DIR" \
    --argjson projects "$projects_json" \
    '{version: 1, base_dir: $base, default_base_branch: "develop", projects: $projects}'
)"

# --update: 기존 값 보존, 새 프로젝트만 추가, 기존 프로젝트는 그대로
if [ "$UPDATE_MODE" -eq 1 ] && orch_settings_exists; then
    new_settings="$(jq --slurpfile cur "$ORCH_SETTINGS" '
        . as $new |
        ($cur[0] // {}) as $old |
        {
          version: ($old.version // $new.version),
          base_dir: ($old.base_dir // $new.base_dir),
          default_base_branch: ($old.default_base_branch // $new.default_base_branch),
          projects: ($new.projects | to_entries | map(
            .key as $k | .value as $v |
            {key: $k, value: ($old.projects[$k] // $v)}
          ) | from_entries)
        }
    ' <<<"$new_settings")"
fi

printf '%s\n' "$new_settings" >"$ORCH_SETTINGS"

echo "OK: $ORCH_SETTINGS 작성 완료"
echo "── 추론된 내용 (직접 편집해 보강하세요) ──"
cat "$ORCH_SETTINGS"
echo "──────────────────────────────────────────"
echo "다음 단계:"
echo "  1. 위 settings.json 의 description / tech_stack 손보세요"
echo "  2. /orch:up 으로 orch pane 등록"
echo "  3. /orch:mp-up MP-XX 로 첫 leader 띄우기"
