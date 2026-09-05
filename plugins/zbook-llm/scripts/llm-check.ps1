<#
  llm-check.ps1 — 로컬 LLM 연동 검증. 서버·BIOS 설정을 변경하지 않는다.
  종료코드: 0=PASS / 1=서버 준비 안 됨 / 2=API·인증 불일치 / 3=추론 실패
  공개된 로컬 키의 적용 여부를 검사하며 프로세스 신원을 보증하지 않는다.
#>
[CmdletBinding()]
param([ValidateRange(1, 65535)][int]$Port = 8080)

$Key = 'ns-local'
$Base = "http://127.0.0.1:$Port"
function Out-Line([string]$s) { Write-Output "[llm-check] $s" }

function Assert-AuthRejected([hashtable]$Headers, [string]$Label) {
    $status = $null
    try {
        $null = Invoke-RestMethod "$Base/v1/models" -Headers $Headers -TimeoutSec 3 -ErrorAction Stop
    } catch {
        if ($null -ne $_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        if ($status -notin @(401, 403)) {
            throw "$Label 거부 여부를 확인할 수 없음: $($_.Exception.Message)"
        }
    }
    if ($status -notin @(401, 403)) { throw "$Label 요청이 허용됨: API 키 설정 확인 필요" }
}

# 1) 준비 상태. /health는 인증 없이 조회한다.
try {
    $h = Invoke-RestMethod "$Base/health" -TimeoutSec 3 -ErrorAction Stop
    if ($h.status -ne 'ok') { throw "status=$($h.status)" }
    Out-Line '1/3 health: ok'
} catch {
    Out-Line "FAIL(1) 서버 준비 안 됨 — $($_.Exception.Message)"
    Out-Line '기동이 필요하면 /llm-up 실행. 로딩 중이면 기다린 뒤 재검증.'
    exit 1
}

# 2) 올바른 키 허용 + 무인증·틀린 키 거부를 모두 확인한다.
try {
    $models = Invoke-RestMethod "$Base/v1/models" -Headers @{Authorization = "Bearer $Key"} -TimeoutSec 3 -ErrorAction Stop
    $id = $models.data[0].id
    if ($id -isnot [string] -or [string]::IsNullOrWhiteSpace($id)) { throw '유효한 모델 ID가 없음' }
    Assert-AuthRejected @{} '무인증'
    Assert-AuthRejected @{Authorization = 'Bearer zbook-check-invalid-key'} '틀린 키'
    $model = Split-Path $id -Leaf
    Out-Line "2/3 API·인증: $model (무인증·틀린 키 거부 확인)"
} catch {
    Out-Line "FAIL(2) API·인증 불일치 — $($_.Exception.Message)"
    exit 2
}

# 3) 발견한 모델에 실추론을 요청한다. 정답과 정상 종료가 모두 필요하다.
$body = @{
    model = $id
    messages = @(@{role = 'user'; content = 'Reply with only the single digit answer: 1+1=?'})
    max_tokens = 20
    temperature = 0
    chat_template_kwargs = @{enable_thinking = $false}
} | ConvertTo-Json -Depth 5
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    $r = Invoke-RestMethod "$Base/v1/chat/completions" -Method Post `
        -Headers @{Authorization = "Bearer $Key"} -ContentType 'application/json; charset=utf-8' `
        -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30 -ErrorAction Stop
    $sw.Stop()
    $choice = $r.choices[0]
    $content = $choice.message.content
    if ($content -isnot [string] -or $content.Trim() -cne '2' -or $choice.finish_reason -ne 'stop') {
        throw "정답 '2'와 finish_reason=stop 필요 (finish=$($choice.finish_reason))"
    }
    $sec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Out-Line "3/3 추론: '2' (${sec}초, $($r.usage.total_tokens)토큰)"
} catch {
    Out-Line "FAIL(3) 추론 실패 — $($_.Exception.Message)"
    exit 3
}

Out-Line "PASS — 연동 정상 · $Base · $model · enable_thinking=false 정답 확인"
exit 0
