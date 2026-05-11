#!/usr/bin/env bash
# PAD-60: orch_resolve_worker_id_case — registry 에 'MP-75' 로 등록된 leader 에
# 'mp-75' 또는 'Mp-75' 로 송신해도 등록 case 로 정규화되어야 한다.

set -euo pipefail

ws="$SANDBOX/case-insensitive-target"
mkdir -p "$ws/.orch/workers" "$ws/.orch/runs/MP-75/workers"

# leader registry (대문자 MP-75 로 등록)
cat > "$ws/.orch/workers/MP-75.json" <<'EOF'
{"worker_id":"MP-75","role":"leader","pane_id":"%999","cwd":"/tmp/x"}
EOF

# worker registry (MP-75/server)
cat > "$ws/.orch/runs/MP-75/workers/server.json" <<'EOF'
{"worker_id":"MP-75/server","role":"worker","pane_id":"%998","cwd":"/tmp/x/server"}
EOF

resolve() {
    ORCH_ROOT="$ws/.orch" bash -c '
        source "$0/scripts/lib.sh"
        orch_resolve_worker_id_case "$1"
    ' "$PLUGIN_ROOT" "$1"
}

# 1. 소문자 입력 → 등록 case 로 정규화
got="$(resolve "mp-75")"
[ "$got" = "MP-75" ] || { echo "FAIL: 'mp-75' → '$got' (기대 'MP-75')" >&2; exit 1; }

# 2. mixed case → 등록 case
got="$(resolve "Mp-75")"
[ "$got" = "MP-75" ] || { echo "FAIL: 'Mp-75' → '$got' (기대 'MP-75')" >&2; exit 1; }

# 3. 정확 case → idempotent
got="$(resolve "MP-75")"
[ "$got" = "MP-75" ] || { echo "FAIL: 'MP-75' → '$got' (idempotent 기대 'MP-75')" >&2; exit 1; }

# 4. worker (<scope>/<role>) — 등록의 정확 case 로
got="$(resolve "mp-75/server")"
[ "$got" = "MP-75/server" ] || { echo "FAIL: 'mp-75/server' → '$got' (기대 'MP-75/server')" >&2; exit 1; }

# 5. registry 에 없는 ID → 입력 그대로 (정규화 대상 아님 — 새 leader 송신 등)
got="$(resolve "unknown-99")"
[ "$got" = "unknown-99" ] || { echo "FAIL: 'unknown-99' → '$got' (기대 입력 그대로)" >&2; exit 1; }

# 6. 'orch' 는 그대로
got="$(resolve "orch")"
[ "$got" = "orch" ] || { echo "FAIL: 'orch' → '$got' (기대 'orch')" >&2; exit 1; }

# 7. send.sh 통합 — 'mp-75' 로 송신해도 등록 case 의 leader 에 도착해야 함.
#    위 sandbox 의 ORCH_ROOT 에 orch 가 보낸이로 등록돼야 send.sh 가 from 추론 가능 → orch 도 추가 등록.
cat > "$ws/.orch/workers/orch.json" <<'EOF'
{"worker_id":"orch","role":"orch","pane_id":"%997","cwd":"/tmp/x"}
EOF
out="$(
    ORCH_ROOT="$ws/.orch" \
    ORCH_WORKER_ID=orch \
    bash "$PLUGIN_ROOT/scripts/send.sh" mp-75 'test body' 2>&1 || true
)"
# INFO 메시지에 정규화 흔적
grep -qF "target case 정규화 'mp-75' → 'MP-75'" <<<"$out" \
    || { echo "FAIL: send.sh 가 case 정규화 INFO 출력 안 함"; printf '%s\n' "$out" >&2; exit 1; }
# inbox 파일이 'MP-75.md' 로 생성됐는지
[ -f "$ws/.orch/inbox/MP-75.md" ] \
    || { echo "FAIL: inbox/MP-75.md 미생성 (case 정규화 실패)"; ls "$ws/.orch/inbox/" >&2; exit 1; }
[ -f "$ws/.orch/inbox/mp-75.md" ] \
    && { echo "FAIL: inbox/mp-75.md 가 생성됨 (소문자 inbox 가 남으면 정규화 실패)"; exit 1; }

echo "OK case-insensitive-target-lookup"
