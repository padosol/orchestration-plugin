---
name: prioritize-issues
description: 워크스페이스에 등록된 이슈 트래커(Linear / GitHub / GitLab / Jira) 의 미완료 이슈를 분석해 루브릭 점수 기반 Top N (기본 3) 을 추천한다. /orch:prioritize 호출 시 사용. 메인 컨텍스트 부담을 줄이기 위해 list/get 호출은 서브에이전트(Agent general-purpose) 로 위임하고 메인은 점수표 + 추천만 받는다. issue_tracker=none 워크스페이스에서는 NA 로 종료.
---

# prioritize-issues

## 무엇을 하는가

`.orch/settings.json` 의 `issue_tracker` 설정을 읽어 그에 맞는 트래커에서 미완료 이슈(`Backlog` / `Todo` / `In Progress`) 를 가져오고, 정의된 루브릭으로 점수화 → Top N 을 추천한다.

핵심 원칙: **메인 컨텍스트는 결과 (점수표 + Top N + 추천 next) 만 받는다.** 이슈 description fetch 같은 무거운 read 는 반드시 `Agent(general-purpose)` 서브에이전트에 위임. 메인이 직접 `mcp__linear-server__list_issues` / `gh issue list` / `glab issue list` / `jira issue list` 를 호출하면 description 이 메인 컨텍스트에 누적되어 후속 작업 효율이 떨어진다.

## 절차

### 1. 트래커 확인

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh   # source 용 — 직접 실행 X
```

대신 다음 명령으로 현재 트래커 확인:

```bash
bash -c 'source ${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh && orch_settings_issue_tracker'
```

- 출력 `linear` → 단계 2 (Linear 위임).
- 출력 `github` → 단계 2 (GitHub 위임). `orch_settings_github_issue_repo` 로 repo 도 함께 확보.
- 출력 `gitlab` → 단계 2 (GitLab 위임). `orch_settings_github_issue_repo` (gitlab 환경에서는 `group/project` 로 재해석) 함께 확보.
- 출력 `jira` → 단계 2 (Jira 위임). 사이트 URL / 토큰은 `~/.config/.jira/.config.yml` 사전 등록 가정.
- 출력 `none` → "이슈 트래커 미사용 모드 — prioritize 대상 없음" 안내 후 종료.
- 명령 실패 (`.orch/settings.json` 없음) → "워크스페이스 셋업 안 됨. `/orch:setup` 먼저" 안내 후 종료.

### 2. 서브에이전트 위임 (필수 — 컨텍스트 효율)

`Agent` 도구 (subagent_type=`general-purpose`) 한 번 호출. 프롬프트에 다음을 모두 포함:

#### 2-A. 트래커별 fetch 지시

**linear**:
```
mcp__linear-server__list_issues 로 team=<team> state=Backlog 와 state=Todo (그리고 In Progress) 호출.
team 값은 settings.json 의 첫 프로젝트 또는 사용자가 지정한 team. 미지정 시 Linear 에서 첫 team.
limit 50. 결과의 title / priority / state / id 만 메모. description 은 점수 매기는 데 필요한 항목만 get_issue 로 부분 fetch.
```

**github**:
```
gh issue list --repo <owner/repo> --state open --json number,title,body,labels,state,milestone -L 100
labels 와 title 로 1차 분류. 추가 정보 필요한 N건만 gh issue view <num> --repo <owner/repo> --json body,comments
```

**gitlab**:
```
glab issue list --repo <group/project> --state opened --output json (최대 100건; --per-page 100)
labels 와 title 로 1차 분류. 추가 정보 필요한 N건만 glab issue view <num> --repo <group/project> --output json
```

**jira**:
```
jira issue list --jql 'statusCategory != Done' --plain --columns key,summary,priority,status,labels (또는 --output json -p '...')
labels 와 summary 로 1차 분류. 추가 정보 필요한 N건만 jira issue view <key> --plain
```

#### 2-B. 루브릭 (사용자 지정 가능)

각 차원 0–3 점, 가중치 동일. 합산 점수 기준 정렬:

| 차원 | 의미 | 0 | 3 |
|---|---|---|---|
| **Severity** | 회귀(직전 릴리스 깨짐) > 사고 패턴 > 신규 개선 | 단순 제안 | 데이터 손실/보안/회귀 |
| **Frequency** | 발생/노출 빈도 | 거의 안 만남 | 매 호출/매 setup |
| **Blocking** | 워크어라운드 유무 | 무난한 회피 가능 | 다른 작업 블로커 |
| **Effort** | 역점수 — 작을수록 +3 | 신규 시스템 | 한 줄 fix |
| **Strategic** | 장기 안정성·UX 가치 | 일회성 | 핵심 인프라 |

#### 2-C. 출력 포맷

서브에이전트는 다음 markdown 만 반환 (description 본문, 추가 분석 절대 금지):

```markdown
## 점수표

| 이슈 | 제목 | Sev | Freq | Block | Effort | Strat | 합 |
|---|---|---:|---:|---:|---:|---:|---:|
| PAD-XX | ... | 3 | 2 | 2 | 2 | 2 | 11 |
...

## Top N

1. **PAD-XX — <제목>** (점수)
   - 한 줄 근거 (왜 이 점수인지)
2. ...
3. ...

## 묶음 추천 (선택)

같은 코드 영역이나 의존 관계로 함께 처리하면 효율적인 페어가 있으면 명시. 없으면 생략.
```

서브에이전트 프롬프트에 위 포맷을 그대로 붙여 출력 강제. 메인이 받는 token 을 최소화한다.

### 3. 메인 컨텍스트 — 결과 표시 + 추천 다음 액션

서브에이전트 결과를 그대로 사용자에게 보여주고, 마지막에 한 줄 추천:

> **추천**: 1번 (`PAD-XX`) 부터 픽업 / 또는 묶음 페어 (PAD-XX + PAD-YY) 동시 진행 / 사용자 컨펌 받고 시작.

자동으로 다음 작업을 시작하지 말 것. 우선순위 결정 자체가 사용자 의사결정 영역.

## 인자 / 옵션

명령 인자 (`/orch:prioritize [--top N] [--team <name>] [--state <name>]`):

- `--top N`: 기본 3. 사용자가 5 같은 다른 값 줄 수 있음
- `--team <name>`: Linear team 이름. 미지정 시 settings.json 의 team 또는 첫 team
- `--state <name>`: 기본 Backlog+Todo+In Progress (open 상태 전부). canceled/done 제외

## 자주 하는 실수 (피하라)

- **메인에서 직접 트래커 list 호출 금지** — `mcp__linear-server__list_issues` / `gh issue list` / `glab issue list` / `jira issue list` 모두 서브에이전트 위임 의무. 컨텍스트 효율이 이 스킬의 핵심 이유. 위임 안 하면 스킬 만든 의미 없음.
- **루브릭 임의 변경 금지** — 사용자가 명시적으로 다른 루브릭 요청하지 않으면 위 5차원 그대로. 일관성이 비교 가치.
- **Top N 안에 들지 못한 이슈 자동 무시 금지** — 점수표는 전체 보여주기. Top 은 강조일 뿐, 사용자가 다른 항목을 골라도 OK.
- **자동 실행 금지** — Top 1 이슈로 바로 작업 시작하지 말 것. 사용자가 어느 트랙으로 갈지 결정.
- **canceled / done 이슈 포함 금지** — 의사결정 노이즈만 늘림.

## 종료 안내

결과 출력 후 한 줄로:
- "어느 이슈부터 진행할까요? (번호 또는 PAD-XX 로 알려주세요)"
