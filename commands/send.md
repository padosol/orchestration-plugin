---
description: 다른 워커에게 메시지 전송 (2-tier hub-and-spoke)
argument-hint: <orch|mp-NN|mp-NN/project> <message>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/send.sh:*)
---

다음 명령으로 메시지를 보내세요. **단, 본문에 따옴표·줄바꿈·백틱이 있으면 슬래시 명령 대신 아래 "복잡한 메시지" 패턴을 쓸 것.**

!`${CLAUDE_PLUGIN_ROOT}/scripts/send.sh $ARGUMENTS`

성공하면 메시지 ID와 보낸이→받는이가 출력됩니다. 차단/실패 시 에러 메시지를 사용자에게 그대로 알려주세요.

**worker_id 형식**:
- `orch` — PM
- `mp-NN` — MP-NN의 팀리더 (예: `mp-13`)
- `mp-NN/<project>` — MP-NN 산하 워커 (예: `mp-13/server`)

**복잡한 메시지 (줄바꿈·따옴표·백틱·괄호 포함) — `--file` 모드 권장**:

이 슬래시 명령은 `$ARGUMENTS` 를 bash 명령줄에 그대로 끼우기 때문에 본문에 `'`, `"`, `` ` ``, `$`, `(` 가 있으면 파서가 깨집니다. 다중 줄 / 특수문자 메시지는 **임시 파일에 본문 쓰고 `--file` 로 전달**하는 게 가장 안전합니다.

권장 패턴 (Bash 도구 사용):

```
# 1. 본문을 임시 파일에 쓴다
cat > /tmp/orch-msg.txt <<'ORCH_MSG'
여기에
여러 줄 메시지를
'따옴표' 와 `백틱` 과 (괄호) 포함해서
자유롭게 작성
ORCH_MSG

# 2. 파일 경로 전달
${CLAUDE_PLUGIN_ROOT}/scripts/send.sh <target> --file /tmp/orch-msg.txt
```

`<<'ORCH_MSG'` 의 작은따옴표가 핵심 — heredoc 내부에서 변수 치환·백틱 평가를 막아 본문이 그대로 파일에 들어갑니다. send.sh 호출은 `--file` 만 쓰니 어떤 본문이든 안전.

⚠️ **금지된 호출 패턴**:

```
# ❌ bash -c 안에 heredoc — 외부 따옴표가 본문의 따옴표/괄호와 충돌해 syntax error
bash -c "send.sh <target> <<'EOF' ... EOF"

# ❌ Bash 도구의 한 명령 안에서 cat | python 같은 파이프로 send.sh 결과 가공
# (실패해도 errors.jsonl 에 안 잡힘)
```

직접 셸에서 인터랙티브 입력하는 경우만 `send.sh <target> <<'EOF' ... EOF` heredoc 사용 가능 — Bash 도구 단일 명령 안에서는 위 `--file` 패턴 사용.

**라우팅 정책 (강제)**:
- ✅ `orch ↔ mp-NN` (PM ↔ leader)
- ✅ `mp-NN ↔ mp-NN/x` (leader ↔ 자기 워커)
- ❌ `mp-NN/x ↔ mp-NN/y` (워커끼리 직접 — leader 경유 필요)
- ❌ `mp-NN/x ↔ orch` (워커는 orch에 직접 송신 불가 — leader 경유)
- ❌ `orch ↔ mp-NN/x` (orch는 워커에 직접 송신 불가 — leader에 위임)
- ❌ `mp-NN ↔ mp-MM` (cross-MP 차단)
- ❌ 자기 자신에게 송신

**팁**:
- 답신 불필요면 본문 끝에 `**[답신 불필요]**` 추가 (핑퐁 방지)
- 긴 작업이면 짧은 ack 답신 후 작업 시작
