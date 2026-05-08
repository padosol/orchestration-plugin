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

출력 후 사용자에게:
1. settings.json 내용 보여주고 편집 권유
2. **이어서 `validate-settings` 스킬을 자동 실행** — description/tech_stack 이 실제 프로젝트와 어긋나는지 검증(Next.js/Spring Boot/JDK 버전 등). drift 가 있으면 표로 보고 + 한 건씩 동의받아 settings.json 을 `Edit` 으로 patch.
3. 첫 셋업이라면 `/orch:validate-plugin` 을 1회 호출해 플러그인 자체 위생도 점검 권유 (문법 + 종속어 검출 — 본 환경에서 깨지는 케이스 사전 차단).
4. 다음 단계(`/orch:up` → `/orch:issue-up`) 안내
