# orch-plugin tests

격리 sandbox 에서 hook / 스크립트 시나리오 일괄 검증. **마켓플레이스 plugin install 이나 새 Claude Code 세션 없이** source tree 만으로 회귀 가능.

## 실행

```bash
bash tests/run.sh                          # 전부
bash tests/run.sh 10-wait-reply-happy      # 특정 시나리오만 (확장자 빼고)
```

출력은 시나리오별 PASS/FAIL 한 줄, 끝에 합계. 상세 로그는 `tests/.last-run.log` 에.

## 구조

- `run.sh` — entrypoint. sandbox wipe → 시나리오 순회 → 합계.
- `scenarios/*.sh` — 자기 sandbox 하위 디렉토리 만들고 검증. exit 0 = PASS.
- `sandbox/` — 매 실행마다 wipe 되는 격리 워크스페이스 (gitignored).
- `.last-run.log` — 최근 실행 상세 출력 (gitignored).

시나리오 prefix 는 실행 순서 의도 (`01-` 먼저). 의존 없이 독립 실행 보장.

## 시나리오 컨트랙트

각 `scenarios/*.sh` 는:
- `set -euo pipefail` 권장.
- 환경변수 `PLUGIN_ROOT` (source tree 루트), `SANDBOX` (격리 디렉토리 루트) 사용.
- 자기만의 하위 디렉토리 `$SANDBOX/<scenario-name>/` 안에서 작업 (다른 시나리오 간섭 없게).
- 마지막에 `echo "OK <name>"` 로 성공 신호.

## 현재 시나리오

| 파일 | 검증 대상 |
|---|---|
| `01-validate-harness-missing.sh` | 누락 alias → systemMessage JSON 발행 |
| `02-validate-harness-clean.sh` | 모든 alias 보유 → silent exit 0 |
| `03-validate-harness-no-settings.sh` | 비-orch 환경 → silent no-op |
| `10-wait-reply-happy.sh` | 사전 도착한 `[reply:<q-id>]` 즉시 캐치 |
| `11-wait-reply-timeout.sh` | 매칭 없음 + timeout → exit 2 |
| `12-wait-reply-ignores-other.sh` | 다른 q-id / 마커 없는 메시지 무시 |
| `20-issue-up-first-msg-has-phase-plan.sh` | leader first_msg 의 Phase Plan 문구 회귀 가드 |
| `21-leader-spawn-first-msg-has-wait-reply.sh` | worker/PM first_msg 의 wait-reply 패턴 회귀 가드 |
| `40-usage-stats-fixture.sh` | usage-stats.py 4 카테고리 카운트 정확성 |
| `41-usage-stats-zero-dead.sh` | usage-stats.py --zero dead 후보 식별 |

## 시나리오 추가

```bash
cp tests/scenarios/10-wait-reply-happy.sh tests/scenarios/30-my-new-test.sh
$EDITOR tests/scenarios/30-my-new-test.sh
chmod +x tests/scenarios/30-my-new-test.sh
bash tests/run.sh 30-my-new-test
```

## 한계

- tmux pane / Claude session spawn 은 검증 못 함 (외부 의존). first_msg 텍스트 검사 (시나리오 20/21) 로 회귀만 가드.
- Phase plan 사용자 컨펌 흐름·실제 worker → leader 라운드트립 같은 라이브 동작은 lol 워크스페이스에서 수동 확인.
