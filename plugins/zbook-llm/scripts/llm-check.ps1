<#
  llm-check.ps1 — 로컬 LLM 연동 3단계 검증 (읽기 전용 — 서버를 띄우지 않는다)

  설계 계약:
    · 검증만 한다. 기동은 /llm-up(llm-up.ps1) 소관 — 실패 시 안내만 남긴다.
    · 포트 생존(1)과 신원(2)을 분리한다 — 8080 점유자가 llama-server라는 보장이 없다.
    · 실추론 왕복(3)까지 가야 PASS다 — health ok 여도 thinking 미해제면 content가 빈 채 온다(2026-09-02 실측).
    · 추론 프롬프트는 ASCII만 쓴다 — 요청 본문 인코딩 변수를 검증 경로에서 제거.

  종료코드: 0=PASS / 1=서버 미가동 / 2=신원 불일치 / 3=추론 실패
#>
$Port = 8080
$Key  = 'ns-local'
$Base = "http://127.0.0.1:$Port"

function Out-Line([string]$s) { Write-Output "[llm-check] $s" }

# 1) 생존 — /health 는 인증 불요
try {
    $h = Invoke-RestMethod "$Base/health" -TimeoutSec 3 -ErrorAction Stop
    if ($h.status -ne 'ok') { throw "status=$($h.status)" }
    Out-Line "1/3 health: ok"
} catch {
    Out-Line "1/3 health: 실패 — $($_.Exception.Message)"
    Out-Line "FAIL(1) 서버 미가동 — 기동: /llm-up 실행 (설치 폴더가 없으면 「로컬AI-설치.zip」의 「2. 설치.bat」 선행)"
    exit 1
}

# 2) 신원 — 포트 점유자가 인증 키를 아는 llama-server 인지
$model = $null
try {
    $id = (Invoke-RestMethod "$Base/v1/models" -Headers @{Authorization = "Bearer $Key"} -TimeoutSec 3 -ErrorAction Stop).data[0].id
    if (-not $id) { throw "모델 목록이 비어 있음" }
    $model = Split-Path $id -Leaf
    Out-Line "2/3 신원: $model"
} catch {
    Out-Line "2/3 신원: 실패 — 포트 $Port 점유자가 llama-server 가 아니거나 키 불일치. $($_.Exception.Message)"
    exit 2
}

# 3) 실추론 왕복 — enable_thinking=false 직답이 실제로 오는지
$body = @{
    model    = 'default'
    messages = @(@{ role = 'user'; content = 'Reply with only the single digit answer: 1+1=?' })
    max_tokens  = 20
    temperature = 0
    chat_template_kwargs = @{ enable_thinking = $false }
} | ConvertTo-Json -Depth 5

$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    $r = Invoke-RestMethod "$Base/v1/chat/completions" -Method Post `
         -Headers @{Authorization = "Bearer $Key"} -ContentType 'application/json' `
         -Body $body -TimeoutSec 30 -ErrorAction Stop
    $sw.Stop()
    $content = $r.choices[0].message.content
    if ([string]::IsNullOrWhiteSpace($content)) {
        Out-Line "3/3 추론: 빈 응답 — thinking 미해제 의심 (finish=$($r.choices[0].finish_reason), $($r.usage.total_tokens)토큰 소모)"
        exit 3
    }
    $sec = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Out-Line "3/3 추론: '$($content.Trim())' (${sec}초, $($r.usage.total_tokens)토큰)"
} catch {
    Out-Line "3/3 추론: 실패 — $($_.Exception.Message)"
    exit 3
}

Out-Line "PASS — 연동 정상 · $Base · $model · enable_thinking=false 직답 확인"
exit 0
