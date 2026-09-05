---
name: llm-check
description: Use when a Windows ZBook local LLM user asks to check connection, readiness, API authentication, or inference, or invokes llm-check. 로컬 AI 연결·상태 확인 요청에 사용한다.
---

# 로컬 AI 연결 확인

설치된 로컬 서버를 검증한다. 상태 확인 요청만으로 서버를 켜거나 재시작하거나 모델을 바꾸지 않는다.

## 실행

이 스킬을 불러온 **실제 `SKILL.md` 절대 경로의 부모 디렉터리**를 `$skillDir`로 지정한다. 현재 작업 폴더나 특정 사용자 설치 경로를 기준으로 삼지 않는다. Windows에서 아래 [공유 스크립트](../../scripts/llm-check.ps1)를 절대 경로로 확인한 뒤 실행한다. 파일이 없거나 Windows가 아니면 실행 불가 사유를 보고한다.

`$llmPort`는 사용자가 지정한 정수 포트이며, 미지정이면 **8080**이다. 허용 범위는 **1–65535**다. 범위 밖 값은 실행하지 않으며 다른 포트나 원격 주소를 임의로 찾지 않는다.

```powershell
$llmScript = (Resolve-Path -LiteralPath (Join-Path $skillDir '../../scripts/llm-check.ps1') -ErrorAction Stop).Path
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $llmScript -Port $llmPort
$checkExit = $LASTEXITCODE
```

종료코드와 출력을 함께 확인한다.

| 종료코드 | 판정 |
|---|---|
| 0 | PASS: 준비 상태, API 인증, 실제 산술 추론 통과 |
| 1 | 서버 준비 안 됨 |
| 2 | API·인증 불일치 |
| 3 | 추론 실패 |

PASS에는 올바른 키 허용, 무인증·틀린 키 거부, 응답 `2`, `finish_reason=stop`이 모두 필요하다. `/health` 성공이나 모델 목록만으로 PASS를 보고하지 않는다. 공개 키 검사는 인증 설정 확인이며 프로세스 신원 증명이 아니다.

3줄 이내로 포트·판정·확인된 모델명, 실제 응답·소요 시간·토큰을 보고한다. 실패한 항목은 관측한 오류와 다음 조치를 적고, 확인하지 못한 모델명이나 수치는 만들지 않는다. 서버가 꺼져 있으면 `llm-up` 스킬을 안내하고 자동 실행하지 않는다. 준비 중이면 기다린 뒤 같은 포트로 재검증한다.

## 이후 로컬 AI를 호출할 때

검증한 `http://127.0.0.1:<포트>`와 인증한 `/v1/models`의 실제 모델 ID를 사용한다. 인증은 `Authorization: Bearer ns-local`이다. 직답 요청에는 `chat_template_kwargs.enable_thinking: false`, 구조화 추출에는 추가로 `temperature: 0`과 `response_format`의 JSON 스키마를 명시한다. 요청 예시와 비교 조건은 [16GB 모델 정책](../../docs/model-policy-16gb.md)을 필요할 때 읽는다.

GPU 메모리는 **16GB 유지**다. 필요하면 `vgm-check` 스킬로 읽기만 한다. PASS를 업무 추출 정확도·요약 신뢰성·4슬롯 장문 성능으로 확대 해석하지 않는다.
