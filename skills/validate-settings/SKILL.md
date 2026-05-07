---
name: validate-settings
description: orch 의 .orch/settings.json 에 적힌 description / tech_stack / kind 가 실제 프로젝트 파일(package.json, build.gradle, pom.xml 등)과 어긋나는지 확인하고 사용자에게 수정을 제안한다. /orch:setup 직후 또는 /orch:validate-settings 호출 시 사용. settings.json 의 정확성이 leader 의 위임 판단에 직결되므로, 버전·프레임워크 명시가 stale 해 보이면 반드시 이 스킬을 호출해 검증해야 한다.
---

# validate-settings

## 무엇을 하는가

`.orch/settings.json` 의 `projects.<alias>.description` 과 `tech_stack` 이 실제 프로젝트 파일과 맞는지 확인한다. 검증 자체는 LLM 의 판단이 들어가기 때문에(예: "Next.js 14 App Router" 라는 문구의 "14" 는 버전이지만 "App Router" 는 아니다) 결정적 신호 추출과 텍스트 비교를 분리한다.

- **결정적 신호**: `scripts/validate-settings.sh` 가 각 프로젝트의 `package.json` / `build.gradle*` / `pom.xml` 에서 프레임워크 버전, JDK, 빌드 파일 종류를 뽑아 JSON 으로 출력
- **판단·제안**: 너(Claude)가 declared description/tech_stack 을 actual 과 대조해 drift 를 찾고, 사용자에게 표로 보고 + 수정 제안

핵심 원칙: **description 이 leader 의 위임 판단 근거**이므로, 버전 숫자·프레임워크 이름·언어 버전이 틀리면 반드시 짚고 넘어간다. 책임/도메인 설명 같은 비-기계적 부분은 건드리지 않는다(추측은 오히려 노이즈).

## 절차

### 1. 신호 추출

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/validate-settings.sh
```

출력은 JSON. `.orch/settings.json` 이 없으면 exit 2 + 안내. 있으면 stdout 에 다음 구조:

```json
{
  "settings_path": "...",
  "default_base_branch": "develop",
  "projects": {
    "ui": {
      "declared": {"path", "kind", "tech_stack", "default_base_branch", "description"},
      "actual":   {"path_exists", "build_files", "frameworks", "jdk", "actual_base_branch"}
    }
  }
}
```

`actual.frameworks` 는 `{"next": {"version": "16.1.6", "major": 16}, ...}` 형태. `actual.jdk` 는 정수. `actual.actual_base_branch` 는 `git remote show origin` 의 HEAD branch (예: `develop`, `main`).

### 2. drift 식별

각 프로젝트마다 다음을 비교한다:

#### A. path_exists
`actual.path_exists == false` → 즉시 ERROR. 경로 자체가 잘못. 수정 후 다시.

#### B. tech_stack 누락/오기
- `actual.frameworks.next` 가 있는데 `declared.tech_stack` 에 `"Next.js"` 없으면 → 추가 제안
- `declared.tech_stack` 에 `"Spring Boot"` 있는데 `actual.frameworks.spring-boot` 없으면 → 제거 제안
- `actual.build_files` 에 `package.json` 있고 `tsconfig.json` 도 있으면 TypeScript (스크립트는 tsconfig 안 봄 — 직접 `Read` 로 확인)

#### C. description 의 버전 숫자 drift (핵심)
description 텍스트에서 다음 정규 패턴을 찾아 actual 과 대조:

| 패턴 | actual 비교 대상 |
|---|---|
| `Next\.js (\d+)` | `frameworks.next.major` |
| `React (\d+)` | `frameworks.react.major` |
| `Spring Boot (\d+)\.(\d+)` | `frameworks.spring-boot.version` 의 첫 두 자리 |
| `JDK (\d+)` / `Java (\d+)` | `jdk` |
| `Vue (\d+)` / `Nuxt (\d+)` | 각각 |

major 차이가 있으면 drift 로 보고. 마이너만 다르면(예: Spring Boot 3.3 → 3.5) 사용자에게 알리되 자동 수정은 보류 — 의도적으로 stale 일 수도 있음.

#### D. default_base_branch (PAD-6)
- `declared.default_base_branch` 미지정이고 `actual.actual_base_branch` 가 글로벌 `default_base_branch` 와 다르면 → **drift 보고 + override 추가 제안**. (예: 글로벌 `develop` 인데 lol-db-schema 의 actual 은 `main` → `projects.db-schema.default_base_branch: "main"` 추가)
- `declared.default_base_branch` 와 `actual.actual_base_branch` 둘 다 있고 다르면 → **불일치 보고**. 사용자에게 어느 쪽이 맞는지 확인. 보통 actual (실제 git 원격) 이 정답이라 declared 를 갱신.
- 둘 다 같거나 declared 가 글로벌 default 와 동일하면 OK.

#### E. kind 정합성
- `frontend-spa` ↔ Next/React/Vue/Nuxt 중 하나라도 있어야
- `backend-api` ↔ spring-boot 또는 다른 서버 프레임워크
- `unknown` 인데 actual 에 명확한 프레임워크 있으면 → 분류 제안
- build_files 가 비어있고 path_exists=true 면 dead/empty 디렉토리 — kind=`unknown` 로 두는게 맞음

### 3. 사용자에게 표 형태로 보고

drift 가 하나라도 있으면 다음 형식으로 보고:

```
## settings.json 검증 — drift <N>건

### ui
- ❌ description "Next.js 14" → 실제 16.1.6 (major 16)
  - 제안: description 의 "Next.js 14" 를 "Next.js 16" 으로

### server
- ⚠️  description "Spring Boot 3.3" → 실제 3.3.6 (일치, 마이너만 명시 가능)
- ✅ JDK 21 일치, kind backend-api 일치

(전부 일치) → "✅ settings.json 모든 프로젝트가 실제 파일과 일치합니다."
```

이모지(❌/⚠️/✅)는 사용자가 한눈에 알아보게 하는 용도라 사용. (이 가이드의 "이모지 금지" 규칙은 코드 파일 대상이고, 사용자 보고용 표 출력은 예외)

### 4. 수정 제안 → 사용자 동의 → Edit

- **major 차이 (D 항목)**: 자동 수정 불가능한 영역까지 건드릴 수 있어, 한 건씩 사용자 확인 받고 `Edit` 으로 settings.json 의 해당 description 만 patch
- **tech_stack 추가/제거**: 동일하게 한 건씩 확인
- **kind 변경**: 영향이 커서 항상 사용자 확인 (leader 의 위임 판단 분기 변경)

수정은 설명 영역에서 **버전 숫자만** 바꾼다. 책임/도메인 설명은 사용자가 직접 쓴 의미가 있으니 임의 재작성 금지.

### 5. drift 없거나 모두 처리되면 종료

종료 메시지는 한 줄: "✅ settings.json 검증 완료" 또는 "⚠️ <N>건 보류 (사용자 검토 필요)".

## 자주 하는 실수 (피하라)

- **마이너 버전 불일치를 자동 수정하지 말 것**. "Spring Boot 3.3" 이 actual 3.3.6 이면 일치로 보고. 3.3 → 3.5 처럼 의미 있게 다른 경우만 수정 제안.
- **description 의 책임/도메인 부분을 손대지 말 것**. 너의 일은 버전 숫자·프레임워크 정합성만이지, "헥사고날 (core/infra 단방향)" 같은 사용자가 직접 쓴 도메인 설명은 절대 재작성 금지.
- **tech_stack 에 너무 자세히 적지 말 것**. `Java`, `Gradle`, `Spring Boot` 정도면 충분 — `JUnit`, `Lombok` 같은 사소한 라이브러리까지 추가 제안하면 노이즈.
- **build_files 가 비어있다고 무조건 kind=unknown 으로 강제하지 말 것**. 사용자가 의도적으로 deploy/infra 디렉토리에 description 만 쓴 경우가 있다.
- **자동 적용 금지**. 항상 사용자에게 표로 보여주고 "수정할까요?" 묻고 한 건씩 처리. 한 번에 모두 수정하면 사용자가 어떤 변경이 일어났는지 추적하기 어렵다.

## 보고 후 다음 단계

검증 끝나면 사용자에게:
- drift 없음 → "다음: `/orch:up` → `/orch:mp-up MP-XX`"
- drift 있고 모두 처리됨 → 같음
- 보류 항목 있음 → 사용자가 직접 settings.json 편집하라고 안내
