---
description: orch 가 큐에 등록한 사용자 질문 목록 / 단건 본문
argument-hint: [<q-id>]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/questions.sh:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/answer.sh:*)
---

다음 명령으로 질문 큐를 조회하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/questions.sh $ARGUMENTS`

**모드 두 가지**:

### 1. 인자 없음 (`/orch:questions`) → 미답 질문 목록
- 헤더의 `open=N answered=N` 으로 미답 / 처리완료 카운트 표시
- 각 행: `id`, `ts` (ISO), `context`, `question` 첫 50자
- 정렬: ts 내림차순 (최신 위)

### 2. id 지정 (`/orch:questions <q-id>`) → 단건 본문 + 선택지
- 본문 + 옵션 표 + 답변 호출 안내
- `status=answered` 면 답변 내용도 함께 표시 (기록 트레이서빌리티)

**답변 흐름**:
1. `/orch:questions` 로 미답 목록 확인
2. `/orch:questions <id>` 로 본문·선택지 확인
3. `/orch:answer <id> <key>` 또는 `/orch:answer <id> --text "<자유>"` 로 답변
4. orch 가 다음 turn 에 inbox 메시지 받아 처리

**id 형식**: `q-<unix-ts>-<rand6>` (예: `q-1778208900-abc123`).

**주의**:
- ❌ 답변 후 `<workspace>/.orch/questions/<id>.json` 직접 삭제 — 의사결정 이력 보존이 의도. answered 상태로만 두고 그대로.
- ❌ 같은 q-id 에 여러 번 답변 — answer.sh 가 status=answered 면 ERROR.
