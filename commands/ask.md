---
description: orch → 사용자 결정 요청 비동기 큐 등록 (선택지 또는 자유 답변)
argument-hint: "<context>" "<question>" --option key=label ... [--allow-freeform]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/ask.sh:*)
---

다음 명령으로 사용자 질문을 큐에 등록하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/ask.sh $ARGUMENTS`

**역할**:
- orch (PM) 가 사용자에게 결정을 요청할 때 비동기 큐에 적재. 즉시 응답 기다리지 않고 다른 작업 (다른 leader 위임 / inbox 정리 / report) 계속 진행 가능.
- 사용자는 자기 페이스로 `/orch:questions` 로 미답 질문 확인 → `/orch:answer <id> <key>` 로 답변.
- 답변이 orch inbox 에 메시지로 도착해 어떤 질문에 대한 답인지 q-id 로 즉시 매핑.

**언제 사용**:
- 질문 여러 개가 한 흐름에 쌓여 사용자가 어느 질문에 답하는지 헷갈리는 패턴
- 결정이 multiline / 여러 선택지인데 plain text 메시지로 묻기 부담스러울 때
- 사용자가 다른 작업 중이라 즉답을 받기 어려운 경우

**언제 사용하지 않을지**:
- 단발성 yes/no, 사전 옵션 2-4개 → `AskUserQuestion` (TUI 동기) 가 더 적합
- 자유 텍스트 짧은 질문 (PR 번호 / 키 / 임의 텍스트) → plain text 한 줄
- 즉답이 필수인 차단 결정 (예: 다음 단계 spawn 분기) → orch 가 inbox 답 도착할 때까지 정말 멈춰야 함을 기억할 것

**호출 예**:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/ask.sh \
    "MP-12 follow-up 결정" \
    "leader 권장 follow-up 6건을 전부 등록할까요?" \
    --option all="전부 등록" \
    --option high_only="High priority 만" \
    --option skip="폐기" \
    --allow-freeform
```

→ stdout: `q-1778208900-abc` (등록된 id)
→ stderr: 안내 (path, context, options, 사용자 안내 문구)

**호출자**: orch pane 전용. leader / worker 가 사용자에게 직접 묻고 싶으면 leader 가 orch 에 escalate → orch 가 ask.sh 호출.

**파일 위치**: `<workspace>/.orch/questions/<id>.json`. 답변되면 같은 파일이 `status: "answered"` + `answer` 채워짐 (별도 archive 디렉토리 없음 — 단일 dir + status 필드).

**보고 형식 — 등록 후**:
- ✅ 좋은 예: `[ask q-1778208900-abc] follow-up 6건 결정 큐에 등록. 사용자 답변 받기 전 다른 마디는 진행 안 합니다.`
- ❌ 나쁜 예: `사용자에게 follow-up 결정 묻겠습니다.` (id 누락)

**주의**:
- ❌ 같은 질문 중복 등록 — 사용자가 같은 결정을 두 번 받음
- ❌ 답변 받기 전에 임의 진행 — 큐에 등록한 의미가 사라짐
- ✅ 등록 직후 사용자에게 q-id 명시한 보고 메시지 1회
