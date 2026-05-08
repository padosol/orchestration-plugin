---
description: orch 가 큐에 등록한 질문에 답변 — 옵션 키 또는 자유 텍스트
argument-hint: <q-id> <key> | <q-id> --text "<답변>"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/answer.sh:*)
---

다음 명령으로 질문에 답변하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/answer.sh $ARGUMENTS`

**모드 두 가지**:

### 1. 옵션 키 — `/orch:answer <q-id> <key>`
- 질문에 등록된 `options[].key` 중 하나 선택
- 예: `/orch:answer q-1778208900-abc all`

### 2. 자유 텍스트 — `/orch:answer <q-id> --text "<답변>"`
- 질문이 `allow_freeform=true` 인 경우만 가능
- 예: `/orch:answer q-1778208900-abc --text "follow-up 1, 3, 5번만 등록"`

**동작**:
- `<workspace>/.orch/questions/<q-id>.json` 의 `status: "answered"` + `answer` 필드 채움
- orch inbox 에 `[answer <q-id>] ...` 메시지 자동 게시 + orch pane 에 `/orch:check-inbox <msg-id>` 전달 → orch 가 다음 turn 에 처리

**검증 (실패 케이스)**:
- 존재 안 하는 q-id → ERROR
- 이미 answered 상태 → ERROR (기존 답변 표시)
- 옵션에 없는 key → 사용 가능 key 안내
- allow_freeform=false 인데 `--text` → ERROR

**id 확인**: `/orch:questions` 로 미답 목록 → `/orch:questions <id>` 로 본문·옵션 확인 후 이 명령.

**주의**:
- ❌ 같은 q-id 두 번 답변 — 결정 이력이 섞임. 새 결정이 필요하면 orch 가 새 질문 등록.
- ❌ 답변 후 질문 파일 직접 삭제 — answered 상태로 보존이 의도 (의사결정 트레이서빌리티).
