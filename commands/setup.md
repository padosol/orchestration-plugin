---
description: orch 프로젝트 메타데이터(.orch/settings.json) 자동 추론 + 작성
argument-hint: [--update]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/validate-settings.sh:*), Read, Edit
---

다음 명령으로 settings.json 을 생성하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh $ARGUMENTS`

**역할**:
- `base_dir/lol-*` 디렉토리를 스캔해 프로젝트 후보를 찾는다
- 각 디렉토리의 `package.json` / `build.gradle` / `pom.xml` 등에서 tech_stack 추론
- `CLAUDE.md` / `README.md` 첫 단락에서 description 추론
- 결과를 `.orch/settings.json` 으로 저장

**사용**:
- `/orch:setup` — 처음 셋업. 이미 있으면 에러.
- `/orch:setup --update` — 기존 값 보존하면서 새 프로젝트만 추가.

**주의**: 자동 추론은 초안일 뿐입니다. **반드시 settings.json을 직접 편집해 description을 정확하게 보강**하세요. 이게 leader 워커가 "어느 프로젝트에 위임할지" 판단하는 근거가 됩니다.

출력 후 사용자에게:
1. settings.json 내용 보여주고 편집 권유
2. **이어서 `validate-settings` 스킬을 자동 실행** — description/tech_stack 이 실제 프로젝트와 어긋나는지 검증(Next.js/Spring Boot/JDK 버전 등). drift 가 있으면 표로 보고 + 한 건씩 동의받아 settings.json 을 `Edit` 으로 patch.
3. 다음 단계(`/orch:up` → `/orch:mp-up`) 안내
