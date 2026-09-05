param([string]$TargetScript, [string]$ScenarioFile)

# Operating-system discovery and HTTP effects are replaced below. NativeArguments
# and CaptureChild run harmless temporary child scripts, never llama-server.
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$global:llmUpScenario = Get-Content -LiteralPath $ScenarioFile -Raw -Encoding UTF8 | ConvertFrom-Json
$global:llmUpEventFile = Join-Path $global:llmUpScenario.temp 'events.jsonl'
function Record([string]$Kind, $Details) {
    @{ kind = $Kind; details = $Details } | ConvertTo-Json -Compress -Depth 8 |
        Add-Content -LiteralPath $global:llmUpEventFile -Encoding UTF8
}

Add-Type -TypeDefinition @'
using System;
public class LlmUpTestResponse { public int StatusCode { get; set; } }
public class LlmUpTestHttpException : Exception {
    public LlmUpTestResponse Response { get; private set; }
    public LlmUpTestHttpException(int status) : base("fixture HTTP " + status) {
        Response = new LlmUpTestResponse { StatusCode = status };
    }
}
'@

if ($global:llmUpScenario.nativeArguments) {
    $global:llmUpArgvScript = Join-Path $global:llmUpScenario.temp 'harmless argv recorder.ps1'
    $env:LLM_UP_TEST_ARGV = Join-Path $global:llmUpScenario.temp 'argv.txt'
    @'
[System.IO.File]::WriteAllLines($env:LLM_UP_TEST_ARGV, [string[]]@(
    $args | ForEach-Object { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_)) }
))
'@ | Set-Content -LiteralPath $global:llmUpArgvScript -Encoding UTF8
}

function Get-CimInstance {
    param($ClassName, $Filter)
    Record 'scan-installation' $null
    [pscustomobject]@{ DeviceID = $global:llmUpScenario.temp }
}
function Get-NetTCPConnection {
    [CmdletBinding()]
    param($LocalPort, $State)
    Record 'listener' @{ port = $LocalPort }
    if ($global:llmUpScenario.busy) { [pscustomobject]@{ OwningProcess = 12345 } }
}
function Get-Process {
    [CmdletBinding()]
    param($Id)
    [pscustomobject]@{ ProcessName = $global:llmUpScenario.processName }
}
function Invoke-RestMethod {
    [CmdletBinding()]
    param([string]$Uri, [hashtable]$Headers, [int]$TimeoutSec, [switch]$UseBasicParsing)
    $kind = 'missing'
    if ($Headers -and $Headers.Authorization) {
        $kind = if ($Headers.Authorization -eq 'Bearer ns-local') { 'correct' } else { 'wrong' }
    }
    $path = ([uri]$Uri).AbsolutePath
    Record 'http' @{ path = $path; key = $kind; timeout = $TimeoutSec }
    if ($path -eq '/health') {
        $status = [int]$global:llmUpScenario.healthStatus
        $body = $global:llmUpScenario.healthBody
    } elseif ($path -eq '/v1/models') {
        if ($kind -eq 'missing') { $status = [int]$global:llmUpScenario.missingStatus }
        elseif ($kind -eq 'wrong') { $status = [int]$global:llmUpScenario.wrongStatus }
        else { $status = [int]$global:llmUpScenario.modelsStatus }
        $body = $global:llmUpScenario.modelsBody
    } else { throw "Unexpected fixture endpoint: $path" }
    if ($status -eq 0) { throw (New-Object System.TimeoutException 'fixture timeout') }
    if ($status -ge 400) { throw (New-Object LlmUpTestHttpException $status) }
    return $body
}
function Start-Process {
    [CmdletBinding()]
    param($FilePath, [string[]]$ArgumentList, $WindowStyle, [switch]$PassThru,
          $RedirectStandardError, $RedirectStandardOutput)
    Record 'start' @{ arguments = $ArgumentList; windowStyle = $WindowStyle; executable = $FilePath }
    if ($global:llmUpScenario.startFault -eq 'throw') { throw 'fixture launch denied' }
    if ($global:llmUpScenario.startFault -eq 'null') { return $null }
    if ($global:llmUpScenario.startupLog) {
        $fixtureLog = Join-Path $global:llmUpScenario.temp 'LLM\logs\server.log'
        $global:llmUpScenario.startupLog | Set-Content -LiteralPath $fixtureLog -Encoding UTF8
    }
    if ($global:llmUpScenario.captureChild) {
        $childScript = Join-Path $global:llmUpScenario.temp 'harmless background child.ps1'
        @'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
[IO.File]::WriteAllText((Join-Path $root 'child-started'), 'started')
Write-Output 'background stdout'
$timer = [Diagnostics.Stopwatch]::StartNew()
while (-not (Test-Path -LiteralPath (Join-Path $root 'release-child')) -and $timer.Elapsed.TotalSeconds -lt 20) {
    Start-Sleep -Milliseconds 50
}
[IO.File]::WriteAllText((Join-Path $root 'child-exited'), 'exited')
# Keep shutdown observably separate from the marker: cleanup must wait for the process.
Start-Sleep -Milliseconds 250
'@ | Set-Content -LiteralPath $childScript -Encoding UTF8
        $launch = @{
            FilePath = "$PSHOME\powershell.exe"
            ArgumentList = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                             '-File', ('"' + $childScript + '"'))
            WindowStyle = $WindowStyle
            PassThru = $true
            ErrorAction = 'Stop'
        }
        if ($RedirectStandardError) { $launch.RedirectStandardError = $RedirectStandardError }
        if ($RedirectStandardOutput) { $launch.RedirectStandardOutput = $RedirectStandardOutput }
        $child = Microsoft.PowerShell.Management\Start-Process @launch
        [IO.File]::WriteAllText((Join-Path $global:llmUpScenario.temp 'child-pid'), [string]$child.Id)
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while (-not (Test-Path -LiteralPath (Join-Path $global:llmUpScenario.temp 'child-started'))) {
            if ($child.HasExited -or $timer.Elapsed.TotalSeconds -ge 5) { throw 'background fixture did not start' }
            Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds 25
        }
        return $child
    }
    if ($global:llmUpScenario.nativeArguments) {
        try {
            $prefix = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                        '-File', ('"' + $global:llmUpArgvScript + '"'))
            $child = Microsoft.PowerShell.Management\Start-Process -FilePath "$PSHOME\powershell.exe" `
                -ArgumentList ($prefix + $ArgumentList) -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
            if ($child.ExitCode -ne 0) { throw "argv recorder failed: $($child.ExitCode)" }
        } catch {
            Record 'native-error' $_.Exception.Message
            throw
        }
    }
    [pscustomobject]@{ Id = 12346; HasExited = [bool]$global:llmUpScenario.processExited; ExitCode = 17 }
}
function Start-Sleep {
    param($Seconds)
    Record 'sleep' @{ seconds = $Seconds }
}

& $TargetScript -Port $global:llmUpScenario.port
if (-not $?) { exit 1 }
exit $LASTEXITCODE
