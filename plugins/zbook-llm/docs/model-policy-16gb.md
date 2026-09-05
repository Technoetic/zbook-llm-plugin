# GPU 16GB 모델 운영 정책 — 0.3.0

한국어 구조화 추출의 정확도를 우선하면 **Qwen3.5-9B-Q8_0**, 응답 속도를 우선하면 **Qwen3.5-4B-Q8_0**를 권장합니다. GPU 메모리 BIOS 설정은 **16GB로 유지**합니다. 아래 비교는 특정 장비·합성 자료의 실험 결과이며, 모든 업무에서 9B가 우수하다는 뜻은 아닙니다.

## 서버와 기본 모델을 보존하는 선택 순서

`llm-up.ps1`은 이미 정상 가동 중인 서버의 준비 상태와 API 인증을 검사하고 그대로 사용합니다. `default.txt`를 바꿔도 현재 서버의 모델은 바뀌지 않습니다. 점유 서버의 준비·인증 검사가 실패하면 중단합니다.

새로 기동할 때는 다음 순서로 이미 설치된 파일을 선택합니다.

1. `<드라이브>:\LLM\models\default.txt`가 지정한 유효한 GGUF 파일. 내용은 경로 없이 파일명 하나여야 하며 `models` 폴더에 실제 파일이 있어야 합니다. 기존 4B 지정도 우선합니다.
2. `Qwen3.5-9B-Q8_0.gguf`
3. `Qwen3.5-4B-Q8_0.gguf`
4. 위 선택이 모두 불가능하면 `mmproj*.gguf`를 제외한 가장 작은 GGUF. 크기가 같으면 파일명 순서입니다.

2·3번은 지정한 파일명과 일치하는 모델만 찾습니다(대소문자 구분 없음). `mmproj*.gguf`는 멀티모달 보조 파일이므로 자동 선택에서 제외합니다. `default.txt`에 명시한 파일은 별도로 존중하므로 주 모델 GGUF만 지정하세요. 사용할 파일이 없으면 중단합니다. 자동 다운로드, `default.txt` 덮어쓰기, 기존 서버 종료·재시작은 하지 않습니다.

## 다음 기동에 사용할 모델 지정

PowerShell에서 설치 드라이브와 원하는 파일명을 확인한 뒤 실행하세요. 이 명령은 모델 파일이 이미 존재하는지 확인한 후 지정 파일을 씁니다. 4B로 돌아갈 때도 같은 절차에서 `$modelName`만 바꾸면 됩니다.

```powershell
$modelDir = 'C:\LLM\models' # 실제 설치 드라이브로 수정
$modelName = 'Qwen3.5-9B-Q8_0.gguf'
# 속도를 우선하려면: $modelName = 'Qwen3.5-4B-Q8_0.gguf'

if ([IO.Path]::GetFileName($modelName) -ne $modelName -or
    [IO.Path]::GetExtension($modelName) -ine '.gguf') {
    throw '경로 없이 GGUF 파일명 하나만 지정하세요.'
}
$modelPath = Join-Path $modelDir $modelName
if (-not (Test-Path -LiteralPath $modelPath -PathType Leaf)) {
    throw "설치된 모델 파일이 없습니다: $modelPath"
}
$markerPath = Join-Path $modelDir 'default.txt'
Set-Content -LiteralPath $markerPath -Value $modelName -Encoding UTF8 -ErrorAction Stop
Get-Content -LiteralPath $markerPath -Encoding UTF8
```

현재 서버는 계속 실행됩니다. 즉시 적용이 필요하면 **서버 소유자가 작업 완료를 확인하고 해당 서버만 종료한 뒤** `/llm-up`과 `/llm-check`를 차례로 실행하세요. 직접 기동했다면 기동 출력의 PID로 대상을 확인할 수 있습니다. 전체 `llama-server` 프로세스를 일괄 종료하지 마세요. `/v1/models`에 실제 선택 모델이 표시되고 `/llm-check`가 통과하는지 확인하세요.

## 선택 사항: 검증한 9B 파일 출처

플러그인은 모델을 내려받지 않습니다. 9B가 필요하면 [고정 리비전의 Qwen3.5-9B-Q8_0.gguf](https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/3885219b6810b007914f3a7950a8d1b469d598a5/Qwen3.5-9B-Q8_0.gguf)를 직접 받아 `models` 폴더에 둘 수 있습니다.

| 항목 | 검증한 값 |
|---|---|
| 저장소 | `unsloth/Qwen3.5-9B-GGUF` |
| 리비전 | `3885219b6810b007914f3a7950a8d1b469d598a5` |
| 파일명 | `Qwen3.5-9B-Q8_0.gguf` |
| 크기 | `9527502048` 바이트 |
| SHA-256 | `809626574d0cb43d4becfa56169980da2bb448f2299270f7be443cb89d0a6ae4` |

다운로드가 끝난 뒤 기본 모델로 지정하기 전에 크기와 해시를 비교하세요. 위 리비전은 이번 실험에 사용한 파일을 식별하기 위한 값입니다.

```powershell
$downloadedModel = 'C:\LLM\models\Qwen3.5-9B-Q8_0.gguf' # 실제 설치 드라이브로 수정
if ((Get-Item -LiteralPath $downloadedModel -ErrorAction Stop).Length -ne 9527502048) {
    throw '모델 파일 크기가 일치하지 않습니다.'
}
$expectedHash = '809626574d0cb43d4becfa56169980da2bb448f2299270f7be443cb89d0a6ae4'
if ((Get-FileHash -LiteralPath $downloadedModel -Algorithm SHA256).Hash -ine $expectedHash) {
    throw '모델 파일 SHA-256이 일치하지 않습니다.'
}
'모델 크기·SHA-256 일치'
```

## 구조화 추출 요청 설정

일반 기동 인자는 **4슬롯 × 8192 토큰, 총 컨텍스트 32768**입니다. 서버 기본 temperature **0.8**은 변경하지 않습니다. 구조화 추출 요청은 `temperature: 0`, `chat_template_kwargs.enable_thinking: false`, 업무 항목을 정의한 JSON 스키마를 모두 명시하세요. 비교 실험은 추가로 `seed: 42`, `cache_prompt: false`를 사용했습니다.

아래는 요청 본문 예시입니다. `model`에는 인증한 `/v1/models`에서 확인한 실제 ID를 넣고, `http://127.0.0.1:8080/v1/chat/completions`에 `Authorization: Bearer ns-local`과 `Content-Type: application/json`으로 보냅니다. 짧은 예시 프롬프트이므로 실험의 고정 프롬프트 전체를 재현하지는 않습니다.

```json
{
  "model": "<실제 모델 ID>",
  "temperature": 0,
  "seed": 42,
  "cache_prompt": false,
  "max_tokens": 768,
  "chat_template_kwargs": { "enable_thinking": false },
  "messages": [
    { "role": "system", "content": "주문의 최종 품번·수량·납기·상태를 추출하세요. 명시되지 않은 값은 null, 납기는 근거가 있을 때만 YYYY-MM-DD로 쓰세요. 상태는 active, cancelled, pending 중 하나입니다. 원문에 없는 값을 추측하지 마세요." },
    { "role": "user", "content": "품번 SAMPLE-001, 수량 3개 주문 확정. 납기는 미정." }
  ],
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "order_items",
      "strict": true,
      "schema": {
        "type": "object",
        "properties": {
          "items": {
            "type": "array",
            "maxItems": 16,
            "items": {
              "type": "object",
              "properties": {
                "part_no": { "type": ["string", "null"] },
                "quantity": { "type": ["number", "null"], "minimum": 0 },
                "due_date": { "type": ["string", "null"] },
                "status": { "type": "string", "enum": ["active", "cancelled", "pending"] }
              },
              "required": ["part_no", "quantity", "due_date", "status"],
              "additionalProperties": false
            }
          }
        },
        "required": ["items"],
        "additionalProperties": false
      }
    }
  }
}
```

스키마는 출력 형식을 제한하며 값의 정확도까지 보증하지 않습니다. 결과를 원문과 대조하고 업무 반영 전에 사용자가 확인해야 합니다.

## 2026-09-05 비교 결과와 한계

장비는 HP ZBook Ultra G1a, Ryzen AI Max+ 395, Radeon 8060S, 설치 RAM 64GiB이며 BIOS GPU 메모리는 16GB였습니다. llama.cpp **b10729-458681e1d**, Vulkan, 33/33 레이어 오프로딩 기록, Q8 모델·f16 KV 캐시를 사용했습니다.

합성 한국어 주문 문서 **36개 고유 사례·정답 53행**을 모델별 2회 측정했습니다(모델별 72요청). 데이터와 정답은 에이전트가 작성하고 별도 에이전트가 감사했으며, 실제 Excel·메일이나 사람이 정답을 매긴 업무 자료는 아닙니다. 문서 정답은 행 순서를 제외한 전체 값의 정확한 일치를 뜻합니다.

| 1슬롯·8192 컨텍스트 추출 측정 | 4B Q8 | 9B Q8 |
|---|---:|---:|
| 문서 전체 정답, 각 회차 | 27/36 (75.0%) | 32/36 (88.9%) |
| 요청 지연 중앙값, 72요청 | 1.5767초 | 2.8379초 |
| 요청 지연 p95, nearest-rank | 3.9758초 | 7.1125초 |
| GPU 프로세스 할당량 표본 최댓값 | 4.67GiB | 8.41GiB |

요청은 한 번에 하나씩 보내고, temperature 0·seed 42·thinking false·JSON 스키마·프롬프트 캐시 끄기를 적용했습니다. 두 모델 모두 두 회차의 응답이 36/36건 동일했습니다. **72개의 독립된 고유 사례로 해석할 수 없습니다.** 회차별로 둘 다 정답 24건, 9B만 정답 8건, 4B만 정답 3건, 둘 다 오답 1건이었습니다. 별도 검증자가 모델·런타임·고정 산출물의 해시를 확인하고 정답률·반복 일치·지연·메모리 집계를 재계산했습니다.

9B의 문서 정답률은 13.9%p 높고 지연 중앙값은 약 1.80배였습니다. 다만 **두 모델 모두 매 회차 53행 중 2행을 통째로 누락**했고, 9B도 명시된 품번을 null로 만들거나 없는 연도를 추가한 사례가 있었습니다. 값이 바뀐 행과 행 전체 누락은 구분해야 합니다.

합성 요약 6건씩을 두 에이전트가 모델명을 가리고 평가한 결과, 주 평가의 필수 사실 보존은 **4B 30/41, 9B 29/41**, 중요 사실 보존은 **24/30, 25/30**이었습니다. 근거 없는 주장도 두 모델에 남았고 일부 판정은 평가자 간 이견이 있었습니다. 요약 성능의 우열은 섞여 있으며 사람의 정확도 평가를 대신하지 않습니다.

별도로 9B를 일반 설정인 **4슬롯 × 8192**로 기동하고, 준비·인증·단순 산술 및 동시 산술 4요청을 확인했습니다. 이 짧은 구간에서 GPU 프로세스 할당량 표본 최댓값은 **10.30GiB**였습니다. 메모리 수치는 전용·공유 할당을 합친 `TotalCommitted`의 표본 최댓값으로, 전용 VRAM 상주량이나 순간 최대 사용량을 보증하지 않습니다. 이 확인은 **슬롯마다 8192토큰을 채운 부하 시험이나 동시 처리 지연 벤치마크가 아닙니다.** 1슬롯 지연 수치를 일반 4슬롯 서비스에 그대로 적용하지 마세요.

따라서 9B는 원문을 확인하며 쓰는 추출·초안 도우미의 정확도 우선 선택입니다. 자동 업무 반영 전에는 실제 업무 자료의 사람 정답 평가, 누락·추측값 점검, 필요한 동시성·장문 부하 검증이 남아 있습니다. 기존 계획의 실제 업무 200건 평가도 미완료입니다. 35B의 16GB 적재·성능은 측정하지 않았습니다.
