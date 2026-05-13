#!/usr/bin/env bash
# Regression guard: design-first task graph 의 두 schema 자체 self-check +
# 모든 workflow template 파일이 task-template.schema.json 을 만족하는지 검증.
# python3 + jsonschema (Draft 2020-12) 필요. import 실패 시 FAIL — schema 가 설계
# 산출물의 핵심 계약이라 hard fail 정책.

set -euo pipefail

graph_schema="$PLUGIN_ROOT/references/schemas/task-graph.schema.json"
tmpl_schema="$PLUGIN_ROOT/references/schemas/task-template.schema.json"
tmpl_dir="$PLUGIN_ROOT/references/workflows/task-templates"

[ -f "$graph_schema" ] || { echo "FAIL: $graph_schema 없음" >&2; exit 1; }
[ -f "$tmpl_schema" ] || { echo "FAIL: $tmpl_schema 없음" >&2; exit 1; }
[ -d "$tmpl_dir" ] || { echo "FAIL: $tmpl_dir 없음" >&2; exit 1; }

python3 - "$graph_schema" "$tmpl_schema" "$tmpl_dir" <<'PY'
import json, sys, glob, os

try:
    from jsonschema import Draft202012Validator
except ImportError as e:
    print(f"FAIL: jsonschema import 실패 ({e}). `pip install jsonschema>=4.10` 필요")
    sys.exit(1)

graph_schema_path, tmpl_schema_path, tmpl_dir = sys.argv[1], sys.argv[2], sys.argv[3]

def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)

# 1. schema self-check — meta-schema 위반이면 schema 자체가 깨진 것
graph_schema = load(graph_schema_path)
tmpl_schema = load(tmpl_schema_path)
try:
    Draft202012Validator.check_schema(graph_schema)
except Exception as e:
    print(f"FAIL: task-graph.schema.json self-check 실패: {e}")
    sys.exit(1)
try:
    Draft202012Validator.check_schema(tmpl_schema)
except Exception as e:
    print(f"FAIL: task-template.schema.json self-check 실패: {e}")
    sys.exit(1)

# 2. 모든 task-template/*.json 이 task-template.schema.json 만족
validator = Draft202012Validator(tmpl_schema)
template_files = sorted(glob.glob(os.path.join(tmpl_dir, "*.json")))
if not template_files:
    print(f"FAIL: {tmpl_dir} 에 template JSON 없음")
    sys.exit(1)

failed = []
for path in template_files:
    name = os.path.basename(path)
    try:
        doc = load(path)
    except Exception as e:
        failed.append(f"{name}: JSON parse 실패 — {e}")
        continue
    errors = sorted(validator.iter_errors(doc), key=lambda e: list(e.absolute_path))
    if errors:
        for err in errors:
            loc = "/".join(str(p) for p in err.absolute_path) or "<root>"
            failed.append(f"{name}: {loc} — {err.message}")

if failed:
    print("FAIL: task-template schema 검증 실패")
    for line in failed:
        print(f"  - {line}")
    sys.exit(1)

print(f"OK task-graph-jsonschema-validate (templates checked: {len(template_files)})")
PY
