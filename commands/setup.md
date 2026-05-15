---
description: orch 프로젝트 메타데이터(.orch/settings.json) 자동 추론 + 작성
argument-hint: [--update] [--issue-tracker linear|github|gitlab|none] [--github-repo owner/repo|group/project] [--git-host github|gitlab|none] [--notify on|off]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/config/setup.sh:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/config/validate-settings.sh:*), Read, Edit, AskUserQuestion, ToolSearch
---

**먼저 — update 모드 분기**

`$ARGUMENTS` 에 `--update` 가 있으면 누락된 `--issue-tracker` / `--git-host` / `--notify` 값을 묻지 말고 바로 setup.sh 를 호출한다. update 모드에서 생략한 값은 기존 `.orch/settings.json` 값이 보존된다. 기존 settings.json 이 없으면 setup.sh 가 실패한다.

**fresh setup — 워크스페이스 메타데이터 3 종 결정**

`$ARGUMENTS` 에 다음 3개 인자가 모두 들어있으면 그대로 setup.sh 호출하고 질문 단계 skip:
- `--issue-tracker <linear|github|gitlab|none>`
- `--git-host <github|gitlab|none>`
- `--notify <on|off>`

하나라도 없으면 **`AskUserQuestion` (TUI) 로 누락분만 묻는다**.

**🔧 `AskUserQuestion` 호출 절차 (필수 — 단축 금지)**:

`AskUserQuestion` 은 fresh session 에서 **deferred tool** (스키마 미로드) 로 시작한다. 그냥 호출하면 `InputValidationError` 또는 무반응. 다음 절차 그대로:

1. **스키마 로드** — `ToolSearch` 호출:
   - `query`: `select:AskUserQuestion`
   - `max_results`: `1`
   - 결과의 `<functions>` 블록에 `AskUserQuestion` 정의가 등장해야 호출 가능. 등장 안 하면 폴백 plain text 허용 (단 사용자에게 "AskUserQuestion 도구 로드 실패" 명시).
2. **일괄 호출** — AskUserQuestion 한 번에 최대 4 질문. 누락 3개 모두 한 호출에 묶어 묻는다 (질문당 header ≤ 12자, options 2-4개, label 1-5단어 + description, 권장 옵션 첫 번째에 라벨 끝 `(Recommended)` 표시).
3. **plain text 폴백 금지** — "어떻게 할까요?" / "1/2/3 골라주세요" 같은 텍스트 질문 절대 사용 X (1번 단계 실패 보고 시에만 허용).

**질문 옵션 (이 슬래시 한정)**:

- **Issue tracker** — 누락 시:
  - `Linear (Recommended)` — `mcp__linear-server__get_issue <key>` 로 자동 fetch (Linear MCP 필요)
  - `GitHub Issues` — `gh issue view N` 로 fetch. 추가로 어느 repo (owner/repo) 인지 묻기
  - `GitLab` — `glab issue view` 로 자동 fetch. group/project 를 알 수 있으면 `--github-repo <group/project>` 로 함께 저장
  - `없음` — 트래커 사용 안 함, leader 가 orch 에 spec 직접 요청
- **Git host** — 누락 시:
  - `GitHub (Recommended)` — `gh` 기반 PR/CI/머지 자동화. wait-merge / review / post-merge 흐름.
  - `GitLab` — `glab` 기반 MR/CI/머지 자동화 (gh 동일 흐름). glab CLI 설치 + 인증 필요.
  - `없음` — git 호스트 미사용 (로컬 전용 또는 self-hosted). PR/MR 자동화 미적용.
- **Notify (Slack 알림)** — 누락 시:
  - `Off (Recommended)` — 셋업 안 한 환경에서 소음 없음. webhook URL 따로 안 채우면 어차피 silent
  - `On` — `.notify.slack_enabled=true`. 추가로 `ORCH_SLACK_WEBHOOK` 환경변수나 `.orch/notify.local.json` 셋업 필요

선택 결과를 인자로 조립해 setup.sh 호출. `Issue tracker = GitHub Issues` 면 `--github-repo <owner/repo>` 도 추가 질문 후 함께. `Issue tracker = GitLab` 이고 group/project 를 알 수 있으면 `--github-repo <group/project>` 도 함께 넣는다.

다음 명령으로 settings.json 을 생성하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/config/setup.sh $ARGUMENTS`

**역할**:
- `base_dir/*` 디렉토리를 스캔해 프로젝트 후보를 찾는다 (ORCH_PROJECT_GLOB 으로 패턴 좁힘 가능)
- 각 디렉토리의 `package.json` / `build.gradle` / `pom.xml` 등에서 tech_stack 추론
- `CLAUDE.md` / `README.md` 첫 단락에서 description 추론
- 결과를 `.orch/settings.json` 으로 저장 — `issue_tracker` / `git_host` / `notify.slack_enabled` / 프로젝트별 `default_base_branch` 포함 (root 글로벌 default_base_branch 는 더 이상 사용 안 함 — 0.12.0 부터 제거됨)

**사용**:
- `/orch:setup` — 처음 셋업. 이미 있으면 에러. 누락 메타데이터는 질문.
- `/orch:setup --update` — 기존 값 보존하면서 새 프로젝트만 추가. 메타데이터 변경하려면 해당 인자 명시.
- `/orch:setup --issue-tracker linear` / `--issue-tracker github --github-repo owner/repo` / `--issue-tracker gitlab --github-repo group/project` / `--issue-tracker none` — 트래커 직접 지정.
- `/orch:setup --git-host github|gitlab|none` — git 호스트 지정.
- `/orch:setup --notify on|off` — Slack 알림 master 토글.

**주의**: 자동 추론은 초안일 뿐입니다. **반드시 settings.json을 직접 편집해 description을 정확하게 보강**하세요. 이게 leader 워커가 "어느 프로젝트에 위임할지" 판단하는 근거가 됩니다.

**프로젝트별 default_base_branch 누락 보강 (setup.sh 다음, 항상 선행)**:

setup.sh 의 자동 감지가 실패한 alias (네트워크 끊김, 원격 없음, git 미관리 프로젝트, 또는 이전 버전의 설정 잔재) 가 있을 수 있다. settings.json 을 다시 읽어 보강이 필요한 alias 들을 추출 — `default_base_branch` 가 비어 있고 **아직 `git: false` 로 마킹되지 않은** entry 만:

```bash
jq -r '.projects // {} | to_entries[] | select((.value.default_base_branch // "") == "" and (.value.git // true) != false) | .key' .orch/settings.json
```

빈 결과면 skip. **빈 alias 가 있으면 반드시 처리** — git 관리 프로젝트인데 비어 있으면 worker spawn 시 `origin/<base>` 가 unknown reference 가 되어 작업이 차단된다. git 미관리 프로젝트면 아래 "Git 관리 안함" 옵션으로 명시 마킹해야 다음 `--update` 에서 재질문이 사라진다. (0.12.0 부터 root 글로벌 fallback 제거 — 프로젝트별 키만 의미있음.)

처리 절차:
1. **AskUserQuestion 스키마 로드** — 이미 위에서 로드했으면 skip. fresh 상태면 `ToolSearch select:AskUserQuestion`.
2. **일괄 질문** — AskUserQuestion 한 번에 최대 4 alias. 4 개 넘으면 여러 번에 나눠 호출. 각 질문:
   - `header`: alias 이름 (≤ 12자, 길면 잘라서)
   - `question`: "프로젝트 `<alias>` 의 default base branch?"
   - `options` (3-4개):
     - `main` — 흔한 GitHub 기본
     - `develop` — gitflow 워크플로
     - `Git 관리 안함` — 해당 프로젝트가 git 저장소가 아님. PR/MR/worktree 자동화 미적용.
   - free-form "Other" 은 AskUserQuestion 이 자동 제공.

   **Recommended 결정** (alias 의 path 디렉토리 상태로 분기 — 표 그대로 적용):

   | 상태 | Recommended | 비고 |
   |---|---|---|
   | `git -C <path> symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null` 가 값을 반환 | 그 값 (예: `develop` / `main`) | 가장 정확. 옵션 라벨 끝에 `(Recommended)` 표시. |
   | 감지 실패 + `<path>/.git` 디렉토리 존재 | `main` | 로컬 git 저장소지만 origin/HEAD 미설정 케이스. |
   | 감지 실패 + `<path>/.git` 디렉토리 부재 | `Git 관리 안함` | 아예 git 미관리. |
3. **Edit 으로 settings.json 갱신** — 각 응답에 대해:
   - 일반 브랜치 선택 (main/develop/Other 수동 입력): `Edit` 도구로 `.orch/settings.json` 의 해당 alias 객체 안에 `"default_base_branch": "<값>"` 필드 추가 (path/kind 다음 위치 권장).
   - **`Git 관리 안함` 선택**: `default_base_branch` 는 쓰지 말고 대신 `"git": false` 필드를 alias 객체에 추가. 이 마커는 다음 `--update` 시 재질문을 차단하고, **추후** leader/worker 가 git 의존 단계 (worktree/PR/머지) 를 건너뛰는 근거로 쓰일 예정이다.

     ⚠ **현 시점 caveat — false sense of safety 주의**: leader/worker 로직은 **아직 `"git": false` 마커를 읽지 않는다**. 마커는 현재로서는 보강 단계 재질문 방지 목적만 안전하게 보장한다. git 미관리 프로젝트에 `/orch:issue-up` 위임이 들어가면 worktree/PR 단계에서 cascade fail 한다 — git 미관리 프로젝트 위임 지원은 별도 작업으로 추가 필요.
4. **확인 보고** — "default_base_branch 보강 완료: alias-A=main, alias-B=develop, alias-C=git 미관리, ..." 한 줄로 사용자에게 알림.

이 절차를 건너뛰고 다음 단계 (validate-settings / validate-plugin / 사용자 작업) 로 가지 말 것 — 설정이 미완 상태로 진행되면 issue-up 시점에서 cascade fail.

출력 후 사용자에게:
1. settings.json 내용 보여주고 편집 권유
2. **이어서 `validate-settings` 스킬을 자동 실행** — description/tech_stack 이 실제 프로젝트와 어긋나는지 검증(Next.js/Spring Boot/JDK 버전 등). drift 가 있으면 표로 보고 + 한 건씩 동의받아 settings.json 을 `Edit` 으로 patch.
3. 첫 셋업이라면 `/orch:validate-plugin` 을 1회 호출해 플러그인 자체 위생도 점검 권유 (문법 + 종속어 검출 — 본 환경에서 깨지는 케이스 사전 차단).
4. 다음 단계(`/orch:up` → `/orch:issue-up`) 안내

**증상별 진입점**:
- `fatal: invalid reference: origin/<base>` (worker spawn 시) → 프로젝트의 `default_base_branch` 가 원격에 없거나 비어 있는 경우. `/orch:setup --update` 로 git remote 자동 감지값 다시 받거나 `settings.json` 직접 수정.
