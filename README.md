# orch — tmux 멀티 세션 오케스트레이션 plugin

한 사용자가 `orch` 윈도우에서 운전하고, 워커 세션들이 파일 메일박스로 메시지를 주고받는다.

## Install

```
/plugin marketplace add padosol/padosol-marketplace
/plugin install orch
```

설치 시 scope를 **project**로 선택하면 `<project>/.claude/settings.json`에 `enabledPlugins`로 등록된다 (그 프로젝트에서만 활성화).

## 구성 요소

- `commands/send.md` → `/orch:send <target> <message>`
- `commands/check-inbox.md` → `/orch:check-inbox`
- `commands/status.md` → `/orch:status`
- `hooks/session-start.sh` → SessionStart hook (`LOL_ROLE` 환경변수 기반)
- `scripts/up.sh` / `scripts/down.sh` → tmux 세션 시작/종료 (셸에서 직접 실행)

## 사용

### tmux 세션 시작

셸에서 직접 실행 (Claude 안이 아님):

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/up.sh"
```

→ `metapick` tmux 세션이 뜨고 4개 윈도우(orch/server/ui/repo)에서 claude가 자동 실행된다.
각 워커 윈도우는 `LOL_ROLE` 환경변수로 자기 역할을 안다.

### orch 윈도우에서 작업 분배

```
/orch:send server "새 매치 통계 API 만들어줘. 응답 스키마는 ui와 협의."
```

→ inbox에 추가되고 server 윈도우에 자동으로 `/orch:check-inbox`가 입력된다.
server 워커는 메시지를 처리하고, 필요하면 `/orch:send ui "..."`로 협의를 시작한다.

### 상태 확인

```
/orch:status
```

### 종료

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/down.sh"
```

## 메일박스 위치

프로젝트 루트의 `.orch/` 디렉토리에 생성된다.

- `inbox/<role>.md` — 미처리 메시지
- `archive/<role>-YYYY-MM-DD.md` — 처리 완료된 메시지

## 핑퐁 방지

답신이 필요 없는 알림성 메시지는 본문 끝에 `**[답신 불필요]**`를 붙인다. 받는 워커는 이를 보고 자동 답신을 보내지 않는다.

## 역할 추론

각 워커 세션은 자기 역할을 다음 우선순위로 알아낸다:
1. `LOL_ROLE` 환경변수 (up.sh가 설정)
2. `cwd` 경로 (lol-server / lol-ui / lol-repository / lol)

따라서 `up.sh` 없이 수동으로 띄운 세션도 cwd만 맞으면 정상 동작한다.
