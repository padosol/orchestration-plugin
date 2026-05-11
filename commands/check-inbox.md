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

---

## 특수 라벨 처리 — `[phase-plan <issue_id>]` (orch 전용)

leader 가 `/orch:send orch '[phase-plan <id>] ...'` 로 보낸 phase plan 메시지는 **사용자 컨펌 의무** 인 차단성 메시지다. leader 는 답이 올 때까지 phase 1 워커 spawn 을 막아둔 상태 — 빠른 처리가 곧 작업 진행.

**처리 절차 (이 순서 그대로)**:

1. 단건 모드로 본문 끝까지 읽기 (`/orch:check-inbox <id>`). phase plan 골격 파악: 작업 타입 / 몇 phase / 각 phase 산출물 / 의존 / 위험 포인트. 본문 전체를 그대로 사용자 화면에 표시 — 요약·생략 금지.
2. **반드시 `AskUserQuestion` TUI** 로 사용자 컨펌 받기. plain text 로 "이대로 진행할까요?" 식 자유서술 질문 금지 — 답이 모호 (`응 ㅇㅋ`) 하면 leader 라우팅이 깨진다.

   질문 1개, 3택:
   - **GO** — 그대로 진행 (leader 가 phase 1 시작)
   - **수정** — 변경 요구사항 있음 (사용자가 notes 로 적음)
   - **취소** — 작업 중단 (leader cascade kill)

3. 사용자 답을 받은 즉시 leader 에 forward — 본문 첫 줄에 명시 라벨:

   | 사용자 답 | leader 에 송신할 본문 첫 줄 | 의미 |
   |---|---|---|
   | GO | `[plan-confirm] GO` | phase 1 진입하라 |
   | 수정 | `[plan-revise] <사용자 notes>` | phases.md 갱신 후 재송신 (라운드 N+1) |
   | 취소 | `[plan-cancel] <사유>` | `/orch:issue-down <id>` 로 정리하라 |

   송신은 따옴표·줄바꿈 안전 위해 heredoc:
   ```
   bash -c "$ORCH_BIN_DIR/send.sh <leader_id> <<'ORCH_MSG'
   [plan-confirm] GO
   ORCH_MSG"
   ```

4. forward 송신 후 그 phase-plan 메시지 archive (`inbox-archive.sh <id>`).

**왜 AskUserQuestion 강제?**
- 자유서술 답 (`그래`, `좋아요`, `한 군데 빼고는 ok` 등) 은 GO 인지 수정인지 모호. 라우팅 잘못되면 leader 가 사용자 의도와 다른 방향으로 spawn → PR 비용 회수 불가.
- TUI 의 미리정의 3택이 결정을 강제. 수정 사항은 notes 로 별도 받아 leader 에 그대로 forward.

**금지**:
- ❌ 사용자에게 묻지 않고 GO 자동 forward — leader 가 임의 방향 진행 위험.
- ❌ phase plan 본문 요약·생략 — 사용자가 풀 본문 보고 결정해야 함. AskUserQuestion 호출 직전 본문 전체를 사용자 화면에 보여줄 것.
- ❌ phase-plan 메시지를 일반 `●` 답신처럼 자유서술 회신 — 라벨 규약 깨짐.

---

## 특수 라벨 처리 — `[follow-up-candidates <issue_id>]` (orch 전용)

leader 가 REPORT 생성 후 `/orch:report` 의 7번 (errors_check) / 8번 (ai_ready_check) 단계로 도출한 후속 이슈 **후보** 를 송신할 때 쓰는 라벨. 카테고리는 본문 첫 줄에 `errors_check` 또는 `ai_ready_check` 로 명시됨.

**처리 원칙 (사용자 정책)**: "팀리더가 제공한 이슈들을 사용자와 검토해서 추가". orch 가 임의로 자동 등록 금지. 사용자 검토 후 등록 결정 항목만 트래커에 등록.

**처리 절차**:

1. 단건 모드로 본문 끝까지 읽기. 카테고리 + 후보 목록 (각 후보는 한 줄: 핵심 정보 + suggested_fix) 파악.
2. 사용자 화면에 본문 그대로 표시 + 한 줄 요약 (예: "PAD-N MP 사이클 errors_check 후보 3건 도착").
3. 등록 결정 받기 — 후보 수에 따라 분기:
   - **후보 1건** → `AskUserQuestion` 2택: **등록 / 폐기**.
   - **후보 2~4건** → `AskUserQuestion` 각 후보 항목당 한 질문 (`등록 / 폐기`). 또는 묶음 질문 `전체 등록 / 선별 / 전체 폐기` 후 "선별" 응답이면 plain text 로 항목 번호 받기.
   - **후보 5건 이상** → 사용자에게 plain text 요청 — "등록할 항목 번호를 알려주세요 (예: 1, 3, 5)". 너무 많아 AskUserQuestion 으로 분해 불가.
4. 등록 결정난 항목만 `settings.json` 의 `issue_tracker` 에 따라 분기:
   - `linear` → `mcp__linear-server__save_issue` (team = 본 MP 와 동일, parent = 본 MP issue, priority = 3, labels 는 카테고리에 따라 `bug`+`orch-fix` 또는 `docs`+`ai-ready` — 팀에 존재할 때만)
   - `github` → `gh issue create --repo <github_issue_repo> --title '...' --body '...' --label <카테고리 라벨>` (parent 는 body 에 `Related: #N` 텍스트로)
   - `gitlab` → `glab issue create --repo <repo> --title '...' --description '...' --label <카테고리 라벨>`
   - `none` → 트래커 미사용. 등록 SKIP, 사용자에게 후보 목록만 보여주고 종결.
5. 등록 결과 (생성된 이슈 ID/URL 목록) 를 사용자에게 한 줄 요약. 옵션: leader 가 이미 종료됐을 가능성 높지만, archive 의 REPORT.html 의 `auto_issue` 필드를 사후 갱신할 필요는 없음 (REPORT.html 은 leader 자체 산출물의 스냅샷이므로).
6. follow-up-candidates 메시지 archive.

**금지**:
- ❌ 사용자에게 묻지 않고 후보 자동 등록 — 사용자 정책 위반.
- ❌ 후보 본문 요약·생략 — 사용자가 풀 본문 보고 결정해야 함.
- ❌ 폐기 결정난 후보 archive 직전에 따로 메모 / 메모리 / docs 에 남기지 말 것 — 폐기된 후보가 재발 패턴이면 다음 사이클의 errors_check / ai_ready_check 가 다시 잡아낸다.
