# zbook-tools — ZBook 로컬 AI 플러그인 마켓플레이스

같은 기종 ZBook에 구축한 **로컬 AI 스택(llama.cpp Vulkan + Qwen GGUF, `<드라이브>:\LLM`)**을 Claude Code에서 바로 다루는 플러그인 모음입니다. 0.2.0의 운영 기준은 **GPU 메모리 16GB 유지**입니다. BIOS 변경·재부팅 기능은 제공하지 않습니다.

## 플러그인

### zbook-llm

| 커맨드 | 하는 일 |
|---|---|
| `/llm-check` | 준비 상태 → API·인증 → 실추론 검증. 무인증·틀린 키 거부, `1+1` 정답 `2`와 정상 종료를 확인해야 PASS |
| `/llm-up` | 서버 기동. 기존 서버도 준비 상태와 인증을 검사하며, 실패하면 중복 기동하지 않음 |
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
- 기본 모델은 현재 16GB에서 사용 중인 Qwen3.5-4B-Q8_0입니다. 모델 파일을 자동 다운로드하거나 BIOS 설정을 바꾸지 않습니다. 35B 모델의 16GB 적재·성능은 미측정입니다.
- 스택이 없으면 `/llm-check`는 종료코드 1(서버 미가동), `/llm-up`은 `[중단] 설치 폴더를 찾지 못했다`로 안내합니다 — 설치 패키지의 「2. 설치.bat」이 선행입니다.

## 문제가 생기면

- `/llm-check`의 종료코드: `0` PASS / `1` 서버 준비 안 됨 / `2` API·인증 불일치 / `3` 추론 실패(오답·빈 응답·잘림 포함). 자동으로 기동하거나 재시작하지 않습니다.
- `ns-local`은 공개된 로컬 설정값입니다. 검증 성공은 키 적용과 API 동작을 뜻하며 실행 파일의 신원이나 업무 답변의 정확도를 보증하지 않습니다. 서버는 `127.0.0.1`에만 바인딩합니다.
- 서버 로그: `<드라이브>:\LLM\logs\server.log` · 기동 직후 죽은 경우는 `server-error.txt`(이쪽에만 남습니다)
- 해결이 안 되면 화면 출력을 그대로 복사해 배포자에게 보내 주세요.

## PowerShell 직접 실행 (Codex 등)

Claude Code 플러그인 명령을 지원하지 않는 에이전트도 다음 스크립트를 실행할 수 있습니다. Codex 전용 플러그인으로 등록된다는 뜻은 아닙니다.

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

테스트는 HTTP·프로세스·BIOS 조회를 모의하고, 인자 전달은 무해한 보조 실행 파일로 확인합니다. 실제 LLM 시작·종료나 BIOS 변경은 하지 않습니다. 실제 모델 로딩·Vulkan 동작은 설치된 장비에서 별도 확인해야 합니다.
