---
description: 자기 inbox 확인 후 처리 — 인자 없으면 요약, <id> 주면 단건 본문
argument-hint: [<msg-id>]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/inbox.sh:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/inbox-archive.sh:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/send.sh:*)
---

다음 명령으로 inbox 를 확인하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/inbox.sh $ARGUMENTS`

**모드 두 가지**:

### 1. 인자 없음 (`/orch:check-inbox`) → 요약 표
- `id`, **`reply`** (`●` 답신 필요 / `○` 답신 불필요), `from`, `ts`, `첫 50자` 컬럼의 표 (최신 위 정렬).
- 헤더 라인의 `reply_needed=N` 이 답신 필요 (`●`) 메시지 수.
- **요약만 보고 종료/답신/archive 절대 금지** — 본문을 모르고 처리하면 메시지 의미를 놓칩니다.
- 출력 끝의 "▶ 다음 단계" 가 가리키는 ID 로 단건 모드 호출하세요.

### 2. id 지정 (`/orch:check-inbox <id>`) → 단건 본문 [필수]
- 해당 메시지의 frontmatter + 본문이 출력됩니다.
- 본문 지시대로 작업 수행. 답이 필요하면 `/orch:send <from> <답신>` 으로 회신 (본문에 `**[답신 불필요]**` 있으면 회신 X).
- 처리 끝나면 그 한 건만 archive — Bash 도구로 다음 명령 실행:
  `bash -c "$ORCH_BIN_DIR/inbox-archive.sh <id>"`
- **archive 는 반드시 ID argument 지정** — 인자 없이 호출하면 거부됩니다. `--all` 은 운영 사고 복구용 escape hatch 라 평소 사용 금지.

**왜 단건씩 강제?** — 요약만 보고 archive 일괄 처리하면 본문에 적힌 작업 지시가 묻혀 메시지가 사실상 처리되지 않은 채 사라집니다. 한 건 본문 확인 → 작업 → 답신 → 그 ID 만 archive 패턴이 의무.

**처리 절차 (이 순서 그대로)**:
1. `/orch:check-inbox` (요약) → INBOX_EMPTY 면 "받은 메시지 없음" 답하고 종료
2. 출력의 "▶ 다음 단계" 가 가리키는 ID (= 가장 최신, 표 첫 줄) 로 `/orch:check-inbox <id>` 호출
3. 본문 읽고 작업 수행 + (필요시) `/orch:send <from> <답신>` 으로 답신
4. `bash -c "$ORCH_BIN_DIR/inbox-archive.sh <id>"` 로 그 건만 archive
5. 메시지가 더 있으면 1번부터 반복 (요약 다시 → 다음 ID), 없으면 종료

**보고 형식 강제 — message_id 누락 금지**:

처리 결과를 사용자/leader 에게 보고할 때 **반드시 message_id 를 인용**하라. message_id 가 빠진 보고는 처리 미완료로 간주.

- ✅ 좋은 예: `[id=1778074602-9oovce] mp-7 issue-down 알림 처리. /orch:report mp-7 곧바로 트리거합니다.`
- ❌ 나쁜 예: `mp-7 issue-down 알림 받았어요, report 작성 시작합니다.` (id 누락)

이유: 같은 from 에서 비슷한 본문이 여러 번 올 수 있어 id 없으면 어떤 메시지가 어떻게 처리됐는지 추적 불가.

**금지 사항**:
- ❌ 요약만 본 채로 답신/archive 호출
- ❌ id 인자 없이 단건 처리 시도 (요약 모드는 ID 식별용 1회 호출 한정)
- ❌ `inbox-archive.sh --all` 호출 (평소 사용 금지)
- ❌ 한 턴에 여러 메시지를 묶어 처리
- ❌ 보고에 message_id 누락
- ❌ **답신 필요 (`●`) 메시지가 미답 상태인데 다음 작업 단계 진행** — 본문 의도와 다른 방향으로 일이 진행되어 PR 비용 회수 불가능 사고로 이어집니다. `●` 메시지는 답신 보낸 후에야 다음 마디로 이동.

**worker_id 별 책임 범위**:
- `orch` (PM): 사용자와 대화 + leader 에 위임. 워커에 직접 송신 불가 → leader 경유.
- `<issue_id>` (leader): 자기 이슈의 워커 spawn / 라우팅 / shutdown. 산하 워커가 다른 프로젝트 질문하면 leader 가 받아 그 프로젝트 워커에 전달.
- `<issue_id>/<project>` (worker): worktree 안에서 작업. 외부 통신은 leader($scope) 경유만.

**중요**:
- 작업이 길어질 것 같으면 보낸이에게 짧은 "접수 확인" 답신 먼저 보내고 본 작업 시작
- 자기 권한 밖 일이면 leader/orch 에 escalate (직접 처리 X)
