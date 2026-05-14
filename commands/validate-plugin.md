---
description: 플러그인 자체 위생 검증 — 문법(bash/python/json) + 종속어(절대경로 등) 검출
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/config/validate-plugin.sh:*)
---

다음 명령으로 플러그인을 검증하세요.

!`${CLAUDE_PLUGIN_ROOT}/scripts/config/validate-plugin.sh`

**역할**:
- bash / python / json 파일의 **문법 오류** 검사 (커밋 전 회귀 차단)
- 사용자 환경에 박힌 **절대경로 (예: `/home/<user>/...`)** 같은 종속어 검출 — 다른 사용자 환경에서 깨지거나 일반성 떨어지는 코드 색출

**언제 사용**:
- 플러그인 스크립트 / 슬래시 커맨드 / SKILL 수정 직후 (커밋 전)
- 신규 슬래시·스크립트 추가 후
- `/orch:setup` 직후 1회 (위생 점검)
- CI / pre-commit hook 후보

**종료 코드**:
- `0` — 모든 검증 통과
- `1` — **문법 오류** 있음 (.sh / .py / .json) — 커밋 차단
- `2` — 종속어 **경고** 만 있음 — 커밋 가능하나 일반 사용자 환경에서 깨질 수 있어 검토 권장

**검사 항목**:

| # | 항목 | 도구 | 의미 |
|---|------|------|------|
| 1 | bash 문법 | `bash -n` | 대괄호·인용·heredoc 깨짐 / 변수 expansion 사고 차단 |
| 2 | python 문법 | `ast.parse` | render_report.py / inbox-parse.py 등 타입·들여쓰기 회귀 차단 |
| 3 | JSON 문법 | `jq empty` | plugin.json / settings 스키마 변경 시 사고 차단 |
| 4 | 종속어 검출 | `grep` | `/home/<user>/...` 절대경로가 fallback / 예시에 박힌 경우 검출 |

**예외**:
- `# shellcheck source=...` 주석은 정적 분석 hint 라 종속어 검출 대상에서 제외
- `.git/` / `__pycache__/` 는 자동 제외

**개선 가이드 (warnings 발견 시)**:
- 절대경로 fallback → `${CLAUDE_PLUGIN_ROOT}` 환경변수 사용 (이미 export 됨)
- README/docs 의 예시 path → `<workspace>/` / `<repo>/` 같은 placeholder 로 일반화
- worker_id 형식 (`<issue_id>` / `<issue_id>/<project>`) 은 protocol identifier 이므로 보존 — 검사 대상 아님
