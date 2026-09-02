<#
  llm-up.ps1 — 이미 설치된 AI 서버를 켠다. /llm-up 커맨드가 실행한다(설치 패키지 「3. 켜기」 검증본에서 파생).

  설치 스크립트와 분리한 이유:
    설치 스크립트는 매번 GitHub·HuggingFace 를 먼저 때린다. 사내망이 막힌 날이나
    비행기 안에서는 설치가 멀쩡한데도 "인터넷 연결 실패"로 끝난다.
    이 스크립트는 **인터넷을 전혀 쓰지 않는다.**
#>
[CmdletBinding()]
param([int]$Port = 8080)

$ErrorActionPreference = 'SilentlyContinue'
$KEY = 'ns-local'

function W([string]$m) { Write-Host $m }

# 설치 위치 자동 탐색 — 로컬 고정 디스크의 <드라이브>\LLM
$root = $null
foreach ($d in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
    $c = Join-Path ($d.DeviceID + '\') 'LLM'
    if (Test-Path (Join-Path $c 'models')) { $root = $c; break }
}
if (-not $root) {
    W "[중단] 설치 폴더(<드라이브>:\LLM)를 찾지 못했다."
    W "[다음] 「2. 설치.bat」 을 먼저 실행하라."
    exit 1
}

# 이미 떠 있나
$busy = Get-NetTCPConnection -LocalPort $Port -State Listen -EA SilentlyContinue
if ($busy) {
    $pn = (Get-Process -Id $busy.OwningProcess -EA SilentlyContinue).ProcessName
    if ($pn -eq 'llama-server') {
        $m = try { (Invoke-RestMethod "http://127.0.0.1:$Port/v1/models" -Headers @{Authorization="Bearer $KEY"} -TimeoutSec 3).data[0].id } catch { '?' }
        W "이미 켜져 있습니다."
        W "  모델 : $(Split-Path $m -Leaf)"
        W "  주소 : http://127.0.0.1:$Port   열쇠: $KEY"
        exit 0
    }
    W "[중단] $Port 포트를 다른 프로그램($pn)이 쓰고 있다."
    W "[다음] 그 프로그램을 끄고 다시 실행하거나 관리자에게 알려라."
    exit 1
}

# 실행 파일 — 가장 최신 빌드 폴더(숫자 기준)
$bin = Get-ChildItem (Join-Path $root 'bin') -Directory |
       Sort-Object @{Expression={ $m=[regex]::Match($_.Name,'\d+'); if($m.Success){[int]$m.Value}else{-1} }} -Descending
$exe = $null
foreach ($b in $bin) { $c = Join-Path $b.FullName 'llama-server.exe'; if (Test-Path $c) { $exe = $c; break } }
if (-not $exe) {
    W "[중단] llama-server.exe 를 찾지 못했다(백신이 지웠을 수 있다)."
    W "[다음] 「2. 설치.bat」 을 다시 실행하라. 이미 받은 모델은 다시 받지 않는다."
    exit 1
}

# 모델 — default.txt 우선
$mdir = Join-Path $root 'models'
$name = (Get-Content (Join-Path $mdir 'default.txt') -Raw).Trim()
$model = Get-Item (Join-Path $mdir $name) -EA SilentlyContinue
if (-not $model) { $model = Get-ChildItem "$mdir\*.gguf" | Sort-Object Length | Select-Object -First 1 }
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
$args = @('-m', $model.FullName, '--host','127.0.0.1','--port',"$Port",'-ngl','99',
          '-c','32768','-np','4','-b','2048','-ub','512',
          '--cache-ram','0','--metrics','--api-key',$KEY,'--log-file',$logFile)
$proc = Start-Process -FilePath $exe -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardError $errFile

$ready = $false; $sec = 0
foreach ($i in 1..60) {
    Start-Sleep -Seconds 2; $sec = $i * 2
    if ($proc.HasExited) {
        W ""
        W "[중단] 서버가 $sec 초 만에 죽었다 (종료코드 $($proc.ExitCode))."
        $err = (Get-Content $errFile -Tail 12 -EA SilentlyContinue) -join "`n"
        if ($err) { W "오류:"; W $err } else { W "(오류 출력이 비어 있다)" }
        W "[다음] 위 내용을 복사해 관리자에게 보내라."
        exit 1
    }
    try { if ((Invoke-RestMethod "http://127.0.0.1:$Port/health" -Headers @{Authorization="Bearer $KEY"} -TimeoutSec 2 -EA Stop).status -eq 'ok') { $ready = $true; break } } catch {}
}
if (-not $ready) {
    W "[중단] 서버가 2분 안에 준비되지 않았다."
    $lg = (Get-Content $logFile -Tail 10 -EA SilentlyContinue) -join "`n"
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
W "  끄려면 :  Get-Process llama-server | Stop-Process -Force"
