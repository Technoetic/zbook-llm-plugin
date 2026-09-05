<#
  llm-up.ps1 — 이미 설치된 AI 서버를 켠다. /llm-up 커맨드가 실행한다(설치 패키지 「3. 켜기」 검증본에서 파생).

  설치 스크립트와 분리한 이유:
    설치 스크립트는 매번 GitHub·HuggingFace 를 먼저 때린다. 사내망이 막힌 날이나
    비행기 안에서는 설치가 멀쩡한데도 "인터넷 연결 실패"로 끝난다.
    이 스크립트는 **인터넷을 전혀 쓰지 않는다.**
#>
[CmdletBinding()]
param([ValidateRange(1, 65535)][int]$Port = 8080)

$ErrorActionPreference = 'Stop'
$KEY = 'ns-local'

function W([string]$m) { Write-Host $m }

function Test-ServerReady {
    $base = "http://127.0.0.1:$Port"
    try {
        $health = Invoke-RestMethod "$base/health" -Headers @{Authorization="Bearer $KEY"} -TimeoutSec 3 -EA Stop
    } catch {
        return [pscustomobject]@{ Ready=$false; Retryable=$true; Detail="/health 요청 실패: $($_.Exception.Message)" }
    }
    if ($health.status -ne 'ok') {
        return [pscustomobject]@{ Ready=$false; Retryable=$true; Detail="/health 상태가 ok가 아니다: $($health.status)" }
    }
    try {
        $models = Invoke-RestMethod "$base/v1/models" -Headers @{Authorization="Bearer $KEY"} -TimeoutSec 3 -EA Stop
    } catch {
        return [pscustomobject]@{ Ready=$false; Retryable=$false; Detail="인증한 /v1/models 요청 실패: $($_.Exception.Message)" }
    }
    if ($models.data -isnot [array] -or $models.data.Count -eq 0) {
        return [pscustomobject]@{ Ready=$false; Retryable=$false; Detail='/v1/models 응답에 유효한 모델 목록이 없다.' }
    }
    foreach ($entry in $models.data) {
        if ($entry.id -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.id)) {
            return [pscustomobject]@{ Ready=$false; Retryable=$false; Detail='/v1/models 응답의 모델 ID가 올바르지 않다.' }
        }
    }

    # 공개된 ns-local은 API 설정값이다. 아래 검사는 인증 적용 여부를 확인하며
    # 서버 프로세스의 강한 신원 증명을 제공하지 않는다.
    foreach ($probe in @(
        @{ Label='키 누락'; Headers=@{} },
        @{ Label='잘못된 키'; Headers=@{Authorization="Bearer $KEY-invalid"} }
    )) {
        $rejected = $false
        try {
            $null = Invoke-RestMethod "$base/v1/models" -Headers $probe.Headers -TimeoutSec 3 -EA Stop
        } catch {
            $status = $null
            if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
            if ($status -in @(401, 403)) { $rejected = $true }
            else {
                return [pscustomobject]@{ Ready=$false; Retryable=$false; Detail="$($probe.Label) 인증 검사 실패(401/403 거부 응답 필요): $($_.Exception.Message)" }
            }
        }
        if (-not $rejected) {
            return [pscustomobject]@{ Ready=$false; Retryable=$false; Detail="$($probe.Label) 요청이 허용되었다. API 키 인증이 올바르게 적용되지 않았다." }
        }
    }
    return [pscustomobject]@{ Ready=$true; Retryable=$false; Model=$models.data[0].id; Detail='ok' }
}

# Windows Start-Process는 배열을 공백으로 합친다. 각 인자를 Windows 규칙으로
# 인용해야 모델·로그 경로의 공백, 따옴표 앞/끝의 역슬래시가 보존된다.
function ConvertTo-NativeArgument([string]$Value) {
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

# 이미 떠 있으면 설치 폴더 탐색보다 먼저 확인한다.
try {
    $busy = @(Get-NetTCPConnection -LocalPort $Port -State Listen -EA Stop)
} catch {
    if ($_.FullyQualifiedErrorId -like 'CmdletizationQuery_NotFound*') { $busy = @() }
    else { W "[중단] $Port 포트 상태를 확인하지 못했다: $($_.Exception.Message)"; exit 1 }
}
if ($busy) {
    foreach ($ownerId in ($busy | Select-Object -ExpandProperty OwningProcess -Unique)) {
        try { $pn = (Get-Process -Id $ownerId -EA Stop).ProcessName }
        catch { W "[중단] $Port 포트 점유 프로세스를 확인하지 못했다: $($_.Exception.Message)"; exit 1 }
        if ($pn -ne 'llama-server') {
            W "[중단] $Port 포트를 다른 프로그램($pn)이 쓰고 있다."
            W "[다음] 포트 점유 상태를 확인하거나 관리자에게 알려라."
            exit 1
        }
    }
    $check = Test-ServerReady
    if (-not $check.Ready) {
        W "[중단] 기존 서버가 $Port 포트를 쓰지만 준비·인증 검증에 실패했다."
        W $check.Detail
        W "[다음] 서버 상태·로그·API 키 설정을 확인하라."
        exit 1
    }
    W "이미 켜져 있습니다."
    W "  모델 : $(Split-Path $check.Model -Leaf)"
    W "  주소 : http://127.0.0.1:$Port   열쇠: $KEY"
    exit 0
}

# 설치 위치 자동 탐색 — 로컬 고정 디스크의 <드라이브>\LLM
$root = $null
try {
    foreach ($d in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
        $c = Join-Path ($d.DeviceID + '\') 'LLM'
        if (Test-Path -LiteralPath (Join-Path $c 'models') -PathType Container) { $root = $c; break }
    }
} catch { W "[중단] 설치 위치 탐색 실패: $($_.Exception.Message)"; exit 1 }
if (-not $root) {
    W "[중단] 설치 폴더(<드라이브>:\LLM)를 찾지 못했다."
    W "[다음] 「2. 설치.bat」 을 먼저 실행하라."
    exit 1
}

# 실행 파일 — 가장 최신 빌드 폴더(숫자 기준)
$bin = if (Test-Path -LiteralPath (Join-Path $root 'bin') -PathType Container) { Get-ChildItem -LiteralPath (Join-Path $root 'bin') -Directory |
       Sort-Object @{Expression={ $m=[regex]::Match($_.Name,'\d+'); if($m.Success){[int]$m.Value}else{-1} }} -Descending
}
$exe = $null
foreach ($b in $bin) { $c = Join-Path $b.FullName 'llama-server.exe'; if (Test-Path -LiteralPath $c -PathType Leaf) { $exe = $c; break } }
if (-not $exe) {
    W "[중단] llama-server.exe 를 찾지 못했다(백신이 지웠을 수 있다)."
    W "[다음] 「2. 설치.bat」 을 다시 실행하라. 이미 받은 모델은 다시 받지 않는다."
    exit 1
}

# 모델 — default.txt 우선
$mdir = Join-Path $root 'models'
$model = $null
$defaultFile = Join-Path $mdir 'default.txt'
if (Test-Path -LiteralPath $defaultFile -PathType Leaf) {
    try {
        $name = ([string](Get-Content -LiteralPath $defaultFile -Raw -Encoding UTF8)).Trim()
        if (-not [string]::IsNullOrWhiteSpace($name) -and
            [IO.Path]::GetFileName($name) -eq $name -and [IO.Path]::GetExtension($name) -ieq '.gguf') {
            $candidate = Join-Path $mdir $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $model = Get-Item -LiteralPath $candidate }
        }
    } catch { W "[주의] default.txt를 읽거나 모델을 선택하지 못했다: $($_.Exception.Message)" }
}
if (-not $model) {
    $model = Get-ChildItem -LiteralPath $mdir -Filter '*.gguf' -File |
             Sort-Object Length, Name | Select-Object -First 1
}
if (-not $model) {
    W "[중단] 모델 파일이 없다."
    W "[다음] 「2. 설치.bat」 을 실행하라."
    exit 1
}

W "켜는 중... ($($model.Name))"
$logs = Join-Path $root 'logs'; New-Item -ItemType Directory -Force $logs | Out-Null
$logFile = Join-Path $logs 'server.log'
$errFile = Join-Path $logs 'server-error.txt'
Remove-Item $logFile -Force -EA SilentlyContinue
$serverArgs = @('-m', $model.FullName, '--host','127.0.0.1','--port',"$Port",'-ngl','99',
          '-c','32768','-np','4','-b','2048','-ub','512',
          '--cache-ram','0','--metrics','--api-key',$KEY,'--log-file',$logFile)
$nativeArguments = ($serverArgs | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
try {
    $proc = Start-Process -FilePath $exe -ArgumentList $nativeArguments -WindowStyle Hidden -PassThru -RedirectStandardError $errFile -EA Stop
    if ($null -eq $proc) { throw 'Start-Process가 프로세스 정보를 반환하지 않았다.' }
} catch {
    W "[중단] 서버를 실행하지 못했다: $($_.Exception.Message)"
    W "[다음] 실행 파일·권한·백신 차단 기록을 확인하라."
    exit 1
}

$ready = $false; $sec = 0
$timer = [Diagnostics.Stopwatch]::StartNew()
foreach ($i in 1..60) {
    Start-Sleep -Seconds 2; $sec = [int]$timer.Elapsed.TotalSeconds
    if ($proc.HasExited) {
        W ""
        W "[중단] 서버가 $sec 초 만에 죽었다 (종료코드 $($proc.ExitCode))."
        $err = (Get-Content -LiteralPath $errFile -Tail 12 -Encoding UTF8 -EA SilentlyContinue) -join "`n"
        if ($err) { W "오류:"; W $err } else { W "(오류 출력이 비어 있다)" }
        W "[다음] 위 내용을 복사해 관리자에게 보내라."
        exit 1
    }
    if ($timer.Elapsed.TotalSeconds -ge 120) { break }
    $check = Test-ServerReady
    if ($check.Ready) { $ready = $true; break }
    if (-not $check.Retryable) {
        W "[중단] 실행한 서버의 준비·인증 검증에 실패했다."
        W $check.Detail
        W "[다음] 서버 로그·API 키 설정을 확인하라."
        exit 1
    }
}
if (-not $ready) {
    W "[중단] 서버가 2분 안에 준비되지 않았다."
    if ($check) { W $check.Detail }
    $lg = (Get-Content -LiteralPath $logFile -Tail 10 -Encoding UTF8 -EA SilentlyContinue) -join "`n"
    if ($lg) { W $lg }
    W "[다음] 위 내용을 관리자에게 보내라."
    exit 1
}

W ""
W "켜졌습니다. ($sec 초)"
W "  모델 : $($model.Name)"
W "  주소 : http://127.0.0.1:$Port"
W "  열쇠 : $KEY   <- 브라우저로 접속하면 설정(Settings)에 이 값을 넣어야 합니다"
W ""
W "  끄려면 :  Stop-Process -Id $($proc.Id)"
