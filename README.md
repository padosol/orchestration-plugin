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

## 메일박스 / 디스크 레이아웃

프로젝트 루트의 `.orch/` 디렉토리에 생성된다.

```
.orch/
├── settings.json                          # 프로젝트 메타데이터
├── inbox/<id>.md                          # orch / leader 인박스
├── archive/<id>-YYYY-MM-DD.md             # orch / leader 메시지 archive
├── archive/<scope>-YYYY-MM-DD/            # mp-down 시 scope dir 통째 archive
├── workers/<id>.json                      # orch / leader registry
├── errors.jsonl                           # top-level 에러 로그
└── runs/                                  # 진행 중 MP scope 들 (PAD-3 wrapper)
    └── <scope>/                           # ex. mp-13
        ├── inbox/<role>.md                # leader 산하 워커 인박스
        ├── archive/<role>-YYYY-MM-DD.md
        ├── workers/<role>.json
        ├── worktrees/<project>/           # git worktree
        ├── leader-archive.md
        └── errors.jsonl                   # scope 별 에러 로그
```

- 동시 진행 MP 가 많아져도 `.orch/` 루트가 어수선해지지 않도록 `runs/` 한 단계 wrapper 사용.
- 후방호환: PAD-3 이전에 만들어진 활성 MP 는 `.orch/<scope>/` 평탄 경로에 그대로 남아 있고, 코드가 양쪽을 본다. 진행중인 MP 가 `mp-down` 으로 종료되면 자연 정리.

### 기본 브랜치 (default_base_branch)

워커가 워크트리를 만들 때 base 브랜치는 다음 순서로 결정한다 (PAD-6):

1. `.orch/settings.json` 의 `projects.<alias>.default_base_branch` (프로젝트별 override)
2. 글로벌 `.orch/settings.json` 의 `.default_base_branch`
3. 하드코드 `develop`

`/orch:setup` 은 각 프로젝트의 `git symbolic-ref refs/remotes/origin/HEAD` 로 기본 브랜치를 자동 감지해 프로젝트 entry 에 기록한다. 한 워크스페이스 안에서 `develop` 플로우 repo 와 `main` 플로우 repo 가 섞여 있어도 안전.

원격에 해당 브랜치가 없으면 `leader-spawn` 이 즉시 fail-loud 로 멈춘다 (이전엔 `git fetch` 가 silent 실패한 뒤 `worktree add` 가 `fatal: invalid reference: origin/<base>` 로 죽었다).

### inbox 가 비어 보일 때

`runs/<scope>/inbox/<role>.md` 파일이 0 bytes 면 **현재 처리할 메시지가 없다는 뜻** — 정상 상태다. 처리된 메시지는 `inbox-archive.sh` 가 `archive/<role>-YYYY-MM-DD.md` 로 옮긴 뒤 inbox 파일을 truncate 하므로 빈 파일은 "직전 메시지를 다 처리했다" 는 흔적. 처리 흔적은 archive 파일에서 확인.

## 핑퐁 방지

답신이 필요 없는 알림성 메시지는 본문 끝에 `**[답신 불필요]**`를 붙인다. 받는 워커는 이를 보고 자동 답신을 보내지 않는다.

## 역할 추론

각 워커 세션은 자기 역할을 다음 우선순위로 알아낸다:
1. `LOL_ROLE` 환경변수 (up.sh가 설정)
2. `cwd` 경로 (lol-server / lol-ui / lol-repository / lol)

따라서 `up.sh` 없이 수동으로 띄운 세션도 cwd만 맞으면 정상 동작한다.
