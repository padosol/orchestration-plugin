---
description: orch 프로젝트 메타데이터(.orch/settings.json) 자동 추론 + 작성
argument-hint: [--update] [--issue-tracker linear|github|none] [--github-repo owner/repo]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/validate-settings.sh:*), Read, Edit, AskUserQuestion, ToolSearch
---

**먼저 — 이슈 트래커 선택 (인자에 `--issue-tracker` 가 없을 때)**:

`$ARGUMENTS` 에 `--issue-tracker` 가 이미 들어있으면 그대로 setup.sh 호출. 없으면 **`AskUserQuestion` (TUI) 로 사용자에게 묻는다** (update 모드에서 기존 값 유지하려는 경우는 `--issue-tracker` 생략 가능 — 기존 값 보존됨).

**🔧 `AskUserQuestion` 호출 절차 (필수 — 단축 금지)**:

`AskUserQuestion` 은 fresh session 에서 **deferred tool** (스키마 미로드) 로 시작한다. 그냥 호출하면 `InputValidationError` 또는 무반응. 다음 절차 그대로:

1. **스키마 로드** — `ToolSearch` 호출:
   - `query`: `select:AskUserQuestion`
   - `max_results`: `1`
   - 결과의 `<functions>` 블록에 `AskUserQuestion` 정의가 등장해야 호출 가능. 등장 안 하면 폴백 plain text 허용 (단 사용자에게 "AskUserQuestion 도구 로드 실패" 명시).
2. **호출** — header ≤ 12자 (예: `Issue tracker`), options 2-4개 (label 1-5단어 + description), 권장 옵션 첫 번째에 라벨 끝 `(Recommended)` 표시.
3. **plain text 폴백 금지** — "어떻게 할까요?" / "1/2/3 골라주세요" 같은 텍스트 질문 절대 사용 X (1번 단계 실패 보고 시에만 허용).

질문 옵션 (이 슬래시 한정):
- **Linear (Recommended)** — `mcp__linear-server__get_issue <key>` 로 이슈 컨텍스트 자동 fetch (Linear MCP 서버 필요)
- **GitHub Issues** — `gh issue view N` 로 fetch. 추가로 어느 repo (owner/repo) 인지 묻기
- **없음** — 트래커 사용 안 함, leader 가 orch 에 spec 직접 요청

선택 결과를 `--issue-tracker <value>` 로, github 선택 시 `--github-repo <owner/repo>` 도 함께 인자에 추가해 setup.sh 호출.

다음 명령으로 settings.json 을 생성하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh $ARGUMENTS`

**역할**:
- `base_dir/*` 디렉토리를 스캔해 프로젝트 후보를 찾는다 (ORCH_PROJECT_GLOB 으로 패턴 좁힘 가능)
- 각 디렉토리의 `package.json` / `build.gradle` / `pom.xml` 등에서 tech_stack 추론
- `CLAUDE.md` / `README.md` 첫 단락에서 description 추론
- 결과를 `.orch/settings.json` 으로 저장 — `issue_tracker` 필드 포함

**사용**:
- `/orch:setup` — 처음 셋업. 이미 있으면 에러. 트래커 미지정시 사용자에게 묻기.
- `/orch:setup --update` — 기존 값 보존하면서 새 프로젝트만 추가. 트래커 변경하려면 `--issue-tracker <new>` 명시.
- `/orch:setup --issue-tracker linear` / `--issue-tracker github --github-repo owner/repo` / `--issue-tracker none` — 트래커 직접 지정.

**주의**: 자동 추론은 초안일 뿐입니다. **반드시 settings.json을 직접 편집해 description을 정확하게 보강**하세요. 이게 leader 워커가 "어느 프로젝트에 위임할지" 판단하는 근거가 됩니다.

**default_base_branch 누락 보강 (setup.sh 다음, 항상 선행)**:

setup.sh 의 자동 감지가 실패한 alias (네트워크 끊김, 원격 없음, 또는 이전 버전의 설정 잔재) 가 있을 수 있다. settings.json 을 다시 읽어 누락 alias 들을 추출:

```bash
jq -r '.projects // {} | to_entries[] | select((.value.default_base_branch // "") == "") | .key' .orch/settings.json
```

빈 결과면 skip. **빈 alias 가 있으면 반드시 처리** — 비어 있으면 worker spawn 시 `origin/<base>` 가 unknown reference 가 되어 작업이 차단된다.

처리 절차:
1. **AskUserQuestion 스키마 로드** — fresh 세션이면 deferred. `ToolSearch` 호출:
   - `query`: `select:AskUserQuestion`
   - `max_results`: `1`
2. **일괄 질문** — AskUserQuestion 한 번에 최대 4 alias. 4 개 넘으면 여러 번에 나눠 호출. 각 질문:
   - `header`: alias 이름 (≤ 12자, 길면 잘라서)
   - `question`: "프로젝트 `<alias>` 의 default base branch?"
   - `options` (2-3개):
     - `main (Recommended)` — 흔한 GitHub 기본
     - `develop` — gitflow 워크플로
     - (Recommended 는 alias 의 path 디렉토리에서 `git -C <path> symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null` 로 감지된 값을 첫 옵션으로 두면 정확도 ↑. 감지 실패하면 main 을 Recommended.)
   - free-form "Other" 은 AskUserQuestion 이 자동 제공.
3. **Edit 으로 settings.json 갱신** — 각 응답에 대해:
   - `Edit` 도구로 `.orch/settings.json` 의 해당 alias 객체 안에 `"default_base_branch": "<값>"` 필드 추가 (이미 다른 필드들 사이에 끼워넣을 수 있게 path/kind 다음 위치 권장).
4. **확인 보고** — "default_base_branch 보강 완료: alias-A=main, alias-B=develop, ..." 한 줄로 사용자에게 알림.

이 절차를 건너뛰고 다음 단계 (validate-settings / validate-plugin / 사용자 작업) 로 가지 말 것 — 설정이 미완 상태로 진행되면 issue-up 시점에서 cascade fail.

출력 후 사용자에게:
1. settings.json 내용 보여주고 편집 권유
2. **이어서 `validate-settings` 스킬을 자동 실행** — description/tech_stack 이 실제 프로젝트와 어긋나는지 검증(Next.js/Spring Boot/JDK 버전 등). drift 가 있으면 표로 보고 + 한 건씩 동의받아 settings.json 을 `Edit` 으로 patch.
3. 첫 셋업이라면 `/orch:validate-plugin` 을 1회 호출해 플러그인 자체 위생도 점검 권유 (문법 + 종속어 검출 — 본 환경에서 깨지는 케이스 사전 차단).
4. 다음 단계(`/orch:up` → `/orch:issue-up`) 안내
