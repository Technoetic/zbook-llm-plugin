---
name: llm-up
description: Use when a Windows ZBook user asks to start the installed local LLM server or invokes llm-up. 설치된 로컬 AI 서버를 켜 달라는 요청에 사용한다.
---

# 로컬 AI 기동

이미 설치된 서버를 켠다. 사용자가 상태 확인만 요청했다면 `llm-check` 스킬을 사용한다. 정상 가동 중인 서버와 사용자의 기본 모델 지정을 보존한다.

## 실행과 검증

이 스킬을 불러온 **실제 `SKILL.md` 절대 경로의 부모 디렉터리**를 `$skillDir`로 지정한다. 현재 작업 폴더나 특정 사용자 설치 경로를 기준으로 삼지 않는다. Windows에서 [기동 스크립트](../../scripts/llm-up.ps1)와 [검증 스크립트](../../scripts/llm-check.ps1)를 아래와 같이 절대 경로로 확인한다. 파일이 없거나 Windows가 아니면 실행 불가 사유를 보고한다.

`$llmPort`는 사용자가 지정한 정수 포트이며, 미지정이면 **8080**이다. 허용 범위는 **1–65535**다. 범위 밖 값은 실행하지 않으며 다른 포트나 원격 주소로 바꾸지 않는다.

```powershell
$upScript = (Resolve-Path -LiteralPath (Join-Path $skillDir '../../scripts/llm-up.ps1') -ErrorAction Stop).Path
$checkScript = (Resolve-Path -LiteralPath (Join-Path $skillDir '../../scripts/llm-check.ps1') -ErrorAction Stop).Path
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $upScript -Port $llmPort
$upExit = $LASTEXITCODE
if ($upExit -eq 0) {
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $checkScript -Port $llmPort
    $checkExit = $LASTEXITCODE
}
```

모델 로딩은 약 2분 걸릴 수 있다. 도구의 전체 실행 제한을 설정할 수 있으면 **300000ms**를 사용한다. 도구가 세션 ID를 반환하면 같은 실행이 끝날 때까지 확인한다. 대기 시간이 끝났다는 이유로 기동 명령을 중복 실행하지 않는다.

| 결과 | 보고와 다음 조치 |
|---|---|
| 기동 종료코드가 0이 아님 | 출력의 `[중단]` 원인과 `[다음]` 조치를 전달 |
| 기동 0, 검증 0 | 확인된 포트·모델명·실제 응답·소요 시간을 보고 |
| 기동 0, 검증 1 / 2 / 3 | 각각 준비 안 됨 / API·인증 불일치 / 추론 실패로 보고 |

기존 서버와 새 서버 모두 **같은 포트의 `llm-check.ps1` 종료코드 0**까지 확인해야 연동 성공이다. 올바른 키 허용, 무인증·틀린 키 거부, 실제 응답 `2`, `finish_reason=stop`이 필요하다. 준비 상태만 확인한 결과를 실추론 성공으로 보고하지 않는다.

## 보존할 상태

- 포트 점유·준비·인증 문제는 보고하고 중단한다. 기존 서버를 종료·재시작하거나 중복 기동하지 않는다. 전체 `llama-server` 프로세스를 일괄 종료하지 않는다.
- 모델 선택은 공유 스크립트에 맡긴다. 정상 가동 서버는 4B여도 유지한다. 신규 기동은 유효한 `models/default.txt` 지정 → 설치된 9B Q8 → 4B Q8 → 가장 작은 주 모델 GGUF 순이다. 실제 선택 결과를 확인하며 모델명·파일 경로를 추측하지 않는다.
- 설치가 없으면 설치가 필요하다는 결과를 보고한다. 자동 다운로드나 `default.txt` 덮어쓰기를 하지 않는다. 모델 변경을 별도로 요청받으면 [16GB 모델 정책](../../docs/model-policy-16gb.md)의 파일 확인·다음 기동 지정 절차를 읽는다. 지정 변경은 현재 서버를 바꾸지 않는다.
- GPU 메모리는 **16GB 유지**다. BIOS 변경·재부팅으로 우회하지 않는다. 구조화 추출을 요청받으면 같은 정책의 `temperature: 0`, `chat_template_kwargs.enable_thinking: false`, JSON 스키마를 적용하고 실제 `/v1/models` ID를 사용한다.

검증 PASS는 준비·인증·단순 산술의 성공이다. 업무 정확도나 4슬롯 장문 처리 성능을 보증하지 않는다.
