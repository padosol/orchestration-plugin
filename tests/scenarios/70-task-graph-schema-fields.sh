#!/usr/bin/env bash
# Regression guard: design-first task graph 의 schema 두 파일이 계약 핵심 필드를
# 유지하는지. grep 기반 — 단순 rename / 삭제 회귀를 잡는다. 실제 schema 유효성은
# 시나리오 72 가 jsonschema 로 검증.

set -euo pipefail

graph_schema="$PLUGIN_ROOT/references/schemas/task-graph.schema.json"
tmpl_schema="$PLUGIN_ROOT/references/schemas/task-template.schema.json"
[ -f "$graph_schema" ] || { echo "FAIL: $graph_schema 없음" >&2; exit 1; }
[ -f "$tmpl_schema" ] || { echo "FAIL: $tmpl_schema 없음" >&2; exit 1; }

graph_required=(
    # 최상위 계약
    "issue_id"
    "workflow_version"
    "phase"
    "design"
    "execution"
    # PM / leader 책임 분리
    "proposed_by"
    "approved_by"
    "approved_at"
    "pm_pr"
    "proposed_task_graph"
    "approved_task_graph"
    "revision"
    # task / step 구조
    "TaskDraft"
    "Task"
    "WorkflowStep"
    "WorkflowTemplateName"
    "depends_on"
    "workflow_template"
    "current_step"
    "artifacts"
    # role / status enum — Role enum 전체 (developer/reviewer/pm/integration/leader)
    "developer"
    "reviewer"
    "pm"
    "integration"
    "leader"
    "pending"
    "ready"
    "running"
    "blocked"
    "needs_changes"
    "merged"
    "done"
    "failed"
    "skipped"
)
missing=()
for phrase in "${graph_required[@]}"; do
    if ! grep -qF "\"$phrase\"" "$graph_schema"; then
        # 일부 키워드 (예: enum 값) 는 따옴표 없이 검색
        if ! grep -qF "$phrase" "$graph_schema"; then
            missing+=("graph:$phrase")
        fi
    fi
done

tmpl_required=(
    "name"
    "version"
    "status"
    "steps"
    "id"
    "owner"
    "required"
    "blocking"
    "stable"
    "placeholder"
)
for phrase in "${tmpl_required[@]}"; do
    if ! grep -qF "\"$phrase\"" "$tmpl_schema"; then
        if ! grep -qF "$phrase" "$tmpl_schema"; then
            missing+=("tmpl:$phrase")
        fi
    fi
done

if [ "${#missing[@]}" -gt 0 ]; then
    echo "FAIL: schema 파일에서 다음 필드/토큰 누락:"
    printf '  - %s\n' "${missing[@]}"
    exit 1
fi

echo "OK task-graph-schema-fields"
