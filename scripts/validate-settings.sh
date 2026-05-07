#!/usr/bin/env bash
# /orch:validate-settings — settings.json 의 description / tech_stack 이
# 실제 프로젝트 파일과 어긋나는지 LLM 이 판단할 수 있도록 "사실값" 을
# JSON 으로 덤프한다. 점수/판단은 스킬 쪽에서 한다.
#
# 출력 (stdout, JSON):
# {
#   "settings_path": ".../settings.json",
#   "default_base_branch": "develop",
#   "projects": {
#     "ui": {
#       "declared": { kind, tech_stack, description },
#       "actual":   { path_exists, build_files, frameworks, jdk }
#     },
#     ...
#   }
# }

set -euo pipefail

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=/home/padosol/.claude-marketplaces/local/plugins/orch/scripts/lib.sh
source "${LIB_DIR}/lib.sh"
orch_install_error_trap "$0"

if ! orch_settings_exists; then
    echo "ERROR: $ORCH_SETTINGS 가 없습니다. 먼저 /orch:setup 실행하세요." >&2
    exit 2
fi

# bash 는 결정적 신호를 TSV 로 stdout 에 흘리고, 마지막에 python 이 합쳐서
# 최종 JSON 을 출력한다. TSV 칼럼:
#   alias \t key \t value
# key 종류:
#   path_exists           : "true" / "false"
#   build_file            : 파일명 (여러 번 가능)
#   framework             : "<name>\t<version>\t<major>"  ← 4-칼럼이 됨
#   jdk                   : "21" 등 숫자

emit_framework() {
    # alias name version
    local alias="$1" name="$2" version="$3"
    [ -z "$version" ] && return 0
    # leading non-digit 제거 → major 추출
    local stripped="${version#"${version%%[0-9]*}"}"
    local major="${stripped%%.*}"
    major="${major//[!0-9]/}"
    [ -z "$major" ] && major="null"
    printf '%s\tframework\t%s\t%s\t%s\n' "$alias" "$name" "$version" "$major"
}

read_pkg_version() {
    # package.json 의 dependencies/devDependencies/peerDependencies 에서 패키지 버전 읽기.
    local pkg_json="$1" name="$2"
    [ -f "$pkg_json" ] || return 0
    python3 - "$pkg_json" "$name" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
name = sys.argv[2]
for key in ("dependencies", "devDependencies", "peerDependencies"):
    v = (data.get(key) or {}).get(name)
    if v:
        print(v)
        break
PY
}

# ── 프로젝트 alias 추출 ───────────────────────────────────────────────
mapfile -t ALIASES < <(python3 - "$ORCH_SETTINGS" <<'PY'
import json, sys
for alias in (json.load(open(sys.argv[1])).get("projects") or {}):
    print(alias)
PY
)

# ── 신호 수집 (TSV 로 임시 파일에 적재) ───────────────────────────────
TSV="$(mktemp)"
trap 'rm -f "$TSV"' EXIT

for alias in "${ALIASES[@]}"; do
    project_path="$(python3 - "$ORCH_SETTINGS" "$alias" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print((data.get("projects", {}).get(sys.argv[2]) or {}).get("path", ""))
PY
)"
    {
        if [ -d "$project_path" ]; then
            printf '%s\tpath_exists\ttrue\n' "$alias"

            # JS/TS 프레임워크
            if [ -f "$project_path/package.json" ]; then
                printf '%s\tbuild_file\tpackage.json\n' "$alias"
                for pkg in next react vue nuxt vite svelte @angular/core; do
                    v="$(read_pkg_version "$project_path/package.json" "$pkg")"
                    [ -n "$v" ] && emit_framework "$alias" "$pkg" "$v"
                done
            fi

            # Gradle
            if compgen -G "$project_path/build.gradle*" >/dev/null 2>&1; then
                for f in "$project_path"/build.gradle*; do
                    [ -f "$f" ] && printf '%s\tbuild_file\t%s\n' "$alias" "$(basename "$f")"
                done
                # Spring Boot — id 'org.springframework.boot' version '3.5.9'
                sb_ver="$(grep -hEo "org\.springframework\.boot[^\n]{0,80}version[ '\"]+[0-9]+\.[0-9]+\.[0-9]+" "$project_path"/build.gradle* 2>/dev/null \
                    | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
                [ -n "$sb_ver" ] && emit_framework "$alias" "spring-boot" "$sb_ver"
                # JDK — JavaLanguageVersion.of(21) → sourceCompatibility = '21' → JavaVersion.VERSION_21
                jdk="$(grep -hEo 'JavaLanguageVersion\.of\([0-9]+\)' "$project_path"/build.gradle* 2>/dev/null \
                    | grep -Eo '[0-9]+' | head -1 || true)"
                if [ -z "$jdk" ]; then
                    jdk="$(grep -hE 'sourceCompatibility' "$project_path"/build.gradle* 2>/dev/null \
                        | grep -Eo '[0-9]+' | head -1 || true)"
                fi
                if [ -z "$jdk" ]; then
                    jdk="$(grep -hEo 'JavaVersion\.VERSION_[0-9]+' "$project_path"/build.gradle* 2>/dev/null \
                        | grep -Eo '[0-9]+$' | head -1 || true)"
                fi
                [ -n "$jdk" ] && printf '%s\tjdk\t%s\n' "$alias" "$jdk"
            fi

            # Maven
            if [ -f "$project_path/pom.xml" ]; then
                printf '%s\tbuild_file\tpom.xml\n' "$alias"
                sb_ver="$(awk '/spring-boot-starter-parent/,/<\/parent>/' "$project_path/pom.xml" 2>/dev/null \
                    | grep -Eo '<version>[0-9]+\.[0-9]+\.[0-9]+' \
                    | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
                if [ -z "$sb_ver" ]; then
                    sb_ver="$(grep -Eo '<spring-boot[^>]*>[0-9]+\.[0-9]+\.[0-9]+' "$project_path/pom.xml" 2>/dev/null \
                        | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
                fi
                [ -n "$sb_ver" ] && emit_framework "$alias" "spring-boot" "$sb_ver"
                jdk="$(grep -Eo '<(java\.version|maven\.compiler\.source|maven\.compiler\.release)>[0-9]+' "$project_path/pom.xml" 2>/dev/null \
                    | grep -Eo '[0-9]+' | tail -1 || true)"
                [ -n "$jdk" ] && printf '%s\tjdk\t%s\n' "$alias" "$jdk"
            fi

            # 기타 마커
            for marker in Cargo.toml go.mod requirements.txt pyproject.toml Dockerfile docker-compose.yml docker-compose.yaml; do
                [ -f "$project_path/$marker" ] && printf '%s\tbuild_file\t%s\n' "$alias" "$marker"
            done

            # PAD-6: 실제 원격 기본 브랜치 — declared default_base_branch 와 어긋나면 validate 측에서 flag.
            actual_base="$(timeout 5 git -C "$project_path" remote show origin 2>/dev/null \
                | awk '/HEAD branch:/ {print $NF; exit}')"
            if [ -z "$actual_base" ] || [ "$actual_base" = "(unknown)" ]; then
                actual_base="$(git -C "$project_path" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null \
                    | sed 's@^origin/@@' || true)"
            fi
            [ -n "$actual_base" ] && printf '%s\tactual_base_branch\t%s\n' "$alias" "$actual_base"
        else
            printf '%s\tpath_exists\tfalse\n' "$alias"
        fi
    } >> "$TSV"
done

# ── 최종 JSON ─────────────────────────────────────────────────────────
python3 - "$ORCH_SETTINGS" "$TSV" <<'PY'
import json, sys, collections

settings_path = sys.argv[1]
tsv_path = sys.argv[2]

settings = json.load(open(settings_path))
declared_projects = settings.get("projects") or {}

per_project = collections.defaultdict(lambda: {
    "path_exists": False,
    "build_files": [],
    "frameworks": {},
    "jdk": None,
    "actual_base_branch": None,
})

with open(tsv_path) as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        alias, key = parts[0], parts[1]
        bucket = per_project[alias]
        if key == "path_exists":
            bucket["path_exists"] = parts[2] == "true"
        elif key == "build_file":
            if parts[2] not in bucket["build_files"]:
                bucket["build_files"].append(parts[2])
        elif key == "framework" and len(parts) >= 5:
            name, version, major = parts[2], parts[3], parts[4]
            bucket["frameworks"][name] = {
                "version": version,
                "major": int(major) if major.isdigit() else None,
            }
        elif key == "jdk":
            bucket["jdk"] = int(parts[2]) if parts[2].isdigit() else parts[2]
        elif key == "actual_base_branch":
            bucket["actual_base_branch"] = parts[2]

out = {
    "settings_path": settings_path,
    "default_base_branch": settings.get("default_base_branch"),
    "projects": {},
}
for alias, declared in declared_projects.items():
    out["projects"][alias] = {
        "declared": {
            "path": declared.get("path"),
            "kind": declared.get("kind"),
            "tech_stack": declared.get("tech_stack", []),
            "default_base_branch": declared.get("default_base_branch"),
            "description": declared.get("description", ""),
        },
        "actual": dict(per_project.get(alias, {
            "path_exists": False,
            "build_files": [],
            "frameworks": {},
            "jdk": None,
            "actual_base_branch": None,
        })),
    }
print(json.dumps(out, indent=2, ensure_ascii=False))
PY
