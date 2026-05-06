---
description: 워커 pane 마지막 30줄 + 활동 시각 + inbox 카운트 — 응답 없는 워커 진단용
argument-hint: <worker-id>
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/peek.sh:*)
---

다음 명령으로 peek 합니다.

!`${CLAUDE_PLUGIN_ROOT}/scripts/peek.sh $ARGUMENTS`

**언제 사용**:
- 워커 답신이 한참 없을 때 — 정말 멈췄는지, 긴 작업(빌드/테스트) 중인지 확인
- pane 죽었는지 확인 (status DEAD 가 뜨면 registry 잔재)
- 사용자가 "걔는 뭐 하고 있어?" 같은 질문할 때

**권한**:
- `orch`: 모든 워커 peek 가능
- `mp-NN` (leader): 자기 자신 또는 산하 워커(`mp-NN/*`) 만
- `mp-NN/<project>` (worker): peek 호출 불가

**heartbeat 핑퐁 안 하는 이유**: 인박스 메시지로 ack 을 매번 요구하면 LLM 토큰 낭비. tmux 화면 캡처와 마지막 활동 시각만으로 진단 충분.

**해석 가이드**:
- `last_used` 가 5분 넘게 갱신 안 됐는데 화면이 도구 응답 대기 중이면 → 정말 멈춤. 사용자 결정 받아 kill 후 재spawn.
- `last_used` 최근인데 inbox 가 비어 있으면 → 작업 중. 그냥 기다리기.
- `inbox` 가 누적되어 있는데 오래 비반응이면 → /orch:check-inbox 알림이 안 닿음. 직접 send-keys 로 알림 재시도 또는 재spawn.
