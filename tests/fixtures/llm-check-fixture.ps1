param([string]$Scenario, [string]$ScriptPath)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$ErrorActionPreference = 'Stop'
$modelId = if ($Scenario -eq 'unicode-model') { 'D:\LLM\' + [char]0xBAA8 + [char]0xB378 + '.gguf' } else { 'fixture-model.gguf' }
Add-Type @'
public class FixtureResponse { public int StatusCode { get; set; } }
public class FixtureHttpException : System.Exception {
    public FixtureResponse Response { get; private set; }
    public FixtureHttpException(int status) : base("Fixture HTTP " + status) {
        Response = new FixtureResponse { StatusCode = status };
    }
}
'@

function Invoke-RestMethod {
    [CmdletBinding()]
    param([Parameter(Position=0)][string]$Uri, [string]$Method, [hashtable]$Headers,
          [string]$ContentType, [object]$Body, [int]$TimeoutSec)
    $expectedPort = if ($Scenario -eq 'custom-port') { 18080 } else { 8080 }
    if (([uri]$Uri).Port -ne $expectedPort) { throw 'Wrong port' }
    if ($Uri.EndsWith('/health')) {
        if ($Scenario -eq 'offline') { throw 'Fixture offline' }
        if ($Scenario -eq 'loading') { return @{status='loading'} }
        return @{status='ok'}
    }
    if ($Uri.EndsWith('/v1/models')) {
        if ($Scenario -eq 'bad-key') { throw [FixtureHttpException]::new(401) }
        if ($Headers.Authorization -ne 'Bearer ns-local') {
            if ($Scenario -eq 'probe-offline') { throw 'Fixture network error' }
            if ($Scenario -eq 'probe-loading') { throw [FixtureHttpException]::new(503) }
            $accept = ($Scenario -eq 'no-auth') -or
                      (($Scenario -eq 'any-key') -and $Headers.Authorization)
            if (-not $accept) { throw [FixtureHttpException]::new(401) }
        }
        if ($Scenario -eq 'empty-models') { return @{data=@()} }
        return @{data=@(@{id=$modelId})}
    }
    if ($Uri.EndsWith('/v1/chat/completions')) {
        $bodyText = if ($Body -is [byte[]]) { [Text.Encoding]::UTF8.GetString($Body) } else { $Body }
        $request = $bodyText | ConvertFrom-Json
        if ($Scenario -eq 'unicode-model' -and ($Body -isnot [byte[]] -or $request.model -cne $modelId)) {
            throw 'Unicode model ID must survive UTF-8 byte transport'
        }
        if ($Scenario -eq 'model-id' -and $request.model -ne 'fixture-model.gguf') {
            throw 'Use the discovered model ID'
        }
        if ($request.chat_template_kwargs.enable_thinking -ne $false) { throw 'Thinking was not disabled' }
        $reply = switch ($Scenario) {
            'wrong-answer' { '7' }
            'thinking' { '<think>unfinished reasoning' }
            'empty-answer' { '' }
            default { " 2 `n" }
        }
        $finish = switch ($Scenario) {
            'truncated' { 'length' }
            'missing-finish' { $null }
            default { 'stop' }
        }
        return @{choices=@(@{message=@{content=$reply};finish_reason=$finish});usage=@{total_tokens=20}}
    }
    throw "Unexpected request: $Uri"
}

if ($Scenario -eq 'custom-port') { & $ScriptPath -Port 18080 }
else { & $ScriptPath }
exit $LASTEXITCODE
