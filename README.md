# zbook-tools — ZBook 로컬 AI 플러그인 마켓플레이스

같은 기종 ZBook에 구축한 **로컬 AI 스택(llama.cpp Vulkan + Qwen GGUF, `<드라이브>:\LLM`)**을 Claude Code에서 바로 다루는 플러그인 모음입니다. **0.3.0은 GPU 메모리 16GB를 유지**하며, 한국어 구조화 추출의 정확도를 우선하면 Qwen3.5-9B-Q8_0, 응답 속도를 우선하면 Qwen3.5-4B-Q8_0를 권장합니다. BIOS 변경·재부팅 기능은 제공하지 않습니다.

## 플러그인

### zbook-llm

| 커맨드 | 하는 일 |
|---|---|
| `/llm-check` | 준비 상태 → API·인증 → 실추론 검증. 무인증·틀린 키 거부, `1+1` 정답 `2`와 정상 종료를 확인해야 PASS |
| `/llm-up` | 서버 기동. 정상 가동 중인 서버와 유효한 기본 모델 지정을 보존하며, 준비·인증 검사 실패 시 중복 기동하지 않음 |
| `/vgm-check` | GPU 메모리가 16GB인지 읽기 전용 확인. 설치 RAM과 Windows에서 보이는 RAM을 구분하여 출력 |
| `/vgm-32gb` | 이전 명령 호환용. `/vgm-check`만 실행하며 32GB로 변경하지 않음 |

## 설치 (Claude Code)

```
/plugin marketplace add Technoetic/zbook-llm-plugin
/plugin install zbook-llm@zbook-tools
```

설치 후 Claude Code를 재시작하면 위 커맨드를 사용할 수 있습니다. 로컬 수정본은 원격 배포 전까지 로컬 폴더 설치로 사용하세요.
같은 이름의 커맨드를 이미 갖고 있다면 `/zbook-llm:llm-check`처럼 플러그인 이름을 붙여 부르면 됩니다.

> 로컬 폴더로도 설치할 수 있습니다: `/plugin marketplace add <이 폴더 경로>`
> (이 방식은 폴더를 지우면 플러그인도 깨지므로, 지워지지 않을 위치에 두세요.)

## 전제 조건

- **로컬 AI 설치 패키지**(별도 전달)로 스택이 먼저 깔려 있어야 합니다 — `<드라이브>:\LLM`에 llama-server 런타임과 모델(GGUF), 포트 `8080`, 키 `ns-local` 규약.
- Windows PowerShell 5.1을 사용합니다. VGM 조회는 HP BIOS WMI 제공자가 필요하며, 조회 불가와 16GB 불일치를 성공으로 처리하지 않습니다.
- 모델은 이미 설치된 GGUF에서 선택합니다. 모델 파일을 자동 다운로드하거나 `models\default.txt`를 덮어쓰지 않습니다. 35B 모델의 16GB 적재·성능은 미측정입니다.
- 스택이 없으면 `/llm-check`는 종료코드 1(서버 미가동), `/llm-up`은 `[중단] 설치 폴더를 찾지 못했다`로 안내합니다 — 설치 패키지의 「2. 설치.bat」이 선행입니다.

## 모델 선택과 측정 범위

`/llm-up`은 다음 순서로 동작합니다.

1. 정상 가동 중인 서버가 있으면 해당 모델을 그대로 사용합니다.
2. 새로 기동할 때 `models\default.txt`가 존재하는 GGUF 파일명만 지정하면 그 값을 따릅니다. 기존 4B 지정도 유지합니다.
3. 지정이 없거나 유효하지 않으면 설치된 `Qwen3.5-9B-Q8_0.gguf` → `Qwen3.5-4B-Q8_0.gguf` 순서로 선택합니다.
4. 둘 다 없으면 기존의 최소 크기 GGUF 선택을 사용하되, 자동 선택에서 `mmproj*.gguf` 보조 파일은 제외합니다. 사용할 모델이 없으면 중단합니다.

합성 한국어 추출 36건을 모델별 2회 측정한 결과, 문서 전체 정답은 4B **27/36 (75.0%)**, 9B **32/36 (88.9%)**로 두 회차에서 같았습니다. 요청 지연 중앙값은 각각 **1.5767초 / 2.8379초**였습니다. 실제 Excel·메일이나 사람이 정답을 매긴 업무 자료의 결과가 아니며, 6건의 합성 요약에서는 우열이 섞였습니다. 두 모델 모두 누락과 원문에 없는 값이 남아 있으므로 업무 반영 전 원문·사용자 확인이 필요합니다.

이 측정은 **1슬롯·8192 컨텍스트, 요청별 temperature=0·thinking=false·JSON 스키마** 조건입니다. 일반 기동은 **4슬롯 × 8192 (총 32768)**이며 서버 기본 temperature **0.8**은 바꾸지 않습니다. 기동·인증·산술 검증 PASS가 업무 정확도나 동시 장문 처리 성능을 뜻하지 않습니다.

[16GB 모델 운영 정책](plugins/zbook-llm/docs/model-policy-16gb.md)에 모델 지정 PowerShell, 선택 다운로드 출처·해시, 요청 설정, 측정 조건과 한계를 정리했습니다.

## 문제가 생기면

- `/llm-check`의 종료코드: `0` PASS / `1` 서버 준비 안 됨 / `2` API·인증 불일치 / `3` 추론 실패(오답·빈 응답·잘림 포함). 자동으로 기동하거나 재시작하지 않습니다.
- `ns-local`은 공개된 로컬 설정값입니다. 검증 성공은 키 적용과 API 동작을 뜻하며 실행 파일의 신원이나 업무 답변의 정확도를 보증하지 않습니다. 서버는 `127.0.0.1`에만 바인딩합니다.
- 서버 로그: `<드라이브>:\LLM\logs\server.log`. 로그가 만들어지기 전에 서버가 종료되면 상세 원인 없이 종료코드만 표시될 수 있습니다.
- 해결이 안 되면 화면 출력을 그대로 복사해 배포자에게 보내 주세요.

서버는 출력 리디렉션 없이 숨김 창으로 백그라운드 기동합니다. 호출자가 출력을 수집할 때 서버 종료까지 기다리는 문제를 피하고, 진단 기록은 서버의 `--log-file`로 남깁니다. 이전 버전의 `server-error.txt`는 갱신하지 않으므로 현재 기동의 오류 근거로 사용하지 마세요.

## PowerShell 직접 실행 (Codex 등)

Claude Code 플러그인 명령을 지원하지 않는 에이전트도 다음 스크립트를 실행할 수 있습니다. Codex 전용 플러그인으로 등록된다는 뜻은 아닙니다. Codex 0.150.1에서 legacy import는 시험했으나, 가져온 명령의 `${CLAUDE_PLUGIN_ROOT}` 자동 치환은 검증되지 않았으므로 직접 실행 시 아래 실제 스크립트 경로를 사용하세요.

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\plugins\zbook-llm\scripts\llm-check.ps1
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\plugins\zbook-llm\scripts\vgm-check.ps1
# 서버 기동이 필요할 때
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\plugins\zbook-llm\scripts\llm-up.ps1
```

`llm-check.ps1`과 `llm-up.ps1`은 `-Port 18080`처럼 포트를 지정할 수 있습니다. 기동 후 같은 포트로 `llm-check.ps1`까지 통과해야 추론 사용 가능으로 보고합니다.

## 개발 검증

Windows와 Python 3에서 저장소 루트에서 실행합니다. 별도 Python 패키지는 필요하지 않습니다.

```powershell
python -m unittest discover -s tests -v
```

테스트는 HTTP·프로세스·BIOS 조회를 모의하고, 인자 전달은 무해한 보조 실행 파일로 확인합니다. 무해한 백그라운드 자식 프로세스가 계속 실행되는 동안 출력 수집을 마친 호출자가 반환하는지도 검사합니다. 실제 LLM 시작·종료나 BIOS 변경은 하지 않습니다. 실제 모델 로딩·Vulkan 동작은 설치된 장비에서 별도 확인해야 합니다.
