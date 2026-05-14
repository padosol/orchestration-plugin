#!/usr/bin/env bash
# Regression guard: prioritize-issues SKILL 이 4 트래커 (linear / github / gitlab / jira)
# + none 분기를 모두 cover 하는지 + setup.md 의 GitLab 표기가 "후속 작업" stale 에서
# glab PR/MR 자동화 지원으로 갱신됐는지 정적 검증.

set -euo pipefail

skill="$PLUGIN_ROOT/skills/prioritize-issues/SKILL.md"
setup_md="$PLUGIN_ROOT/commands/setup.md"

[ -f "$skill" ]    || { echo "FAIL: $skill 없음" >&2; exit 1; }
[ -f "$setup_md" ] || { echo "FAIL: $setup_md 없음" >&2; exit 1; }

# 1. frontmatter description 에 Linear / GitHub / GitLab / Jira 모두 등장
fm_block="$(awk '/^---$/{c++; if (c==2) exit; if (c==1) next} c==1' "$skill")"
for tracker in Linear GitHub GitLab Jira; do
    if ! grep -qF "$tracker" <<<"$fm_block"; then
        echo "FAIL: prioritize-issues SKILL frontmatter description 에 '${tracker}' 누락" >&2; exit 1
    fi
done

# 2. §1 트래커 확인 절에 linear / github / gitlab / jira / none 5종 출력 분기
for output in 'linear' 'github' 'gitlab' 'jira' 'none'; do
    if ! grep -qE "출력 .${output}." "$skill"; then
        echo "FAIL: prioritize-issues SKILL 의 트래커 확인 절에 '출력 ${output}' 분기 누락" >&2; exit 1
    fi
done

# 3. §2-A 4 트래커 fetch 지시 — 각 트래커별 실제 list 명령 + 부분 fetch 명령.
#    gitlab 은 glab CLI 1.36+ 가 --output json 미지원 → glab api REST 호출 (projects/:fullpath/issues).
declare -A list_cmd=(
    [linear]='mcp__linear-server__list_issues'
    [github]='gh issue list'
    [gitlab]='glab api'
    [jira]='jira issue list'
)
declare -A view_cmd=(
    [linear]='get_issue'
    [github]='gh issue view'
    [gitlab]='issues/<iid>'
    [jira]='jira issue view'
)
for tracker in linear github gitlab jira; do
    if ! grep -qF "${list_cmd[$tracker]}" "$skill"; then
        echo "FAIL: prioritize-issues SKILL 의 ${tracker} fetch 지시에 '${list_cmd[$tracker]}' 없음" >&2; exit 1
    fi
    if ! grep -qF "${view_cmd[$tracker]}" "$skill"; then
        echo "FAIL: prioritize-issues SKILL 의 ${tracker} fetch 지시에 '${view_cmd[$tracker]}' 없음" >&2; exit 1
    fi
done

# 3b. gitlab 분기는 invalid stale flag (--state opened / --output json) 잔존 금지
if grep -qE 'glab issue list.*--state' "$skill"; then
    echo "FAIL: prioritize-issues SKILL gitlab 분기에 stale 'glab issue list --state ...' 잔존 (glab 1.36+ 미지원)" >&2
    exit 1
fi
if grep -qE 'glab issue view.*--output json' "$skill"; then
    echo "FAIL: prioritize-issues SKILL gitlab 분기에 stale 'glab issue view --output json' 잔존" >&2
    exit 1
fi

# 4. §자주하는 실수 — '메인에서 직접 ... 호출 금지' 가 4 트래커 모두 언급
warn_line="$(grep -E '메인에서 직접' "$skill" || true)"
if [ -z "$warn_line" ]; then
    echo "FAIL: prioritize-issues SKILL 에 '메인에서 직접 ... 호출 금지' 절 없음" >&2; exit 1
fi
for cmd in 'list_issues' 'gh issue list' 'glab' 'jira issue list'; do
    if ! grep -qF "$cmd" <<<"$warn_line"; then
        echo "FAIL: '메인에서 직접 호출 금지' 절에 '${cmd}' 누락" >&2; exit 1
    fi
done

# 5. setup.md GitLab 표기에 "후속 작업" stale 사라지고 PR/MR 자동화 지원 명시
if grep -qE 'metadata 저장만.*PR/MR 자동화는 후속 작업' "$setup_md"; then
    echo "FAIL: setup.md GitLab 표기에 stale 한 'PR/MR 자동화는 후속 작업' 잔존" >&2; exit 1
fi
# Git host 절의 GitLab 라인이 glab 자동화 표기를 가지는지 (한 라인 안에)
if ! grep -qE '.GitLab.*glab.*자동화' "$setup_md"; then
    echo "FAIL: setup.md GitLab 표기에 'glab ... 자동화' 표기 누락" >&2; exit 1
fi

echo "OK prioritize-issues-trackers"
