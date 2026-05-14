---
description: 파일 inbox 에 메시지가 올 때까지 폴링 후 단건 본문 확인
argument-hint: [--timeout SEC] [--interval SEC]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/messages/poll-inbox.sh:*)
---

다음 명령으로 자기 inbox 에 메시지가 도착할 때까지 파일 기반으로 폴링하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/messages/poll-inbox.sh $ARGUMENTS`

용도:
- 새 leader / worker 세션이 첫 지시를 기다릴 때
- `send.sh` 의 tmux 알림 없이 파일 queue 로만 전달되는 leader ↔ worker 메시지를 받을 때
- 이미 inbox 에 메시지가 있으면 즉시 최신 메시지 본문을 출력

출력된 메시지는 본문 지시대로 처리한 뒤 반드시 단건 archive:
`bash -c "$ORCH_BIN_DIR/messages/inbox-archive.sh <id>"`

일반적인 “이미 와 있는 메시지 요약/단건 확인” 은 `/orch:check-inbox` 를 쓰고, “아직 안 온 메시지를 기다림” 은 `/orch:poll-inbox` 를 쓴다.
