param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][string]$ScenarioPath
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$global:VgmFixtureScenario = Get-Content -LiteralPath $ScenarioPath -Raw -Encoding UTF8 | ConvertFrom-Json

function global:Get-CimInstance {
    [CmdletBinding()]
    param([string]$ClassName, [string]$Namespace = 'root/cimv2')
    if ($Namespace -eq 'root\HP\InstrumentedBIOS' -and $ClassName -eq 'HP_BIOSEnumeration') {
        if ($global:VgmFixtureScenario.biosUnavailable) { throw 'Invalid namespace' }
        if ($global:VgmFixtureScenario.settingMissing) { return @() }
        return [pscustomobject]@{
            Name = 'Dedicated Graphics Memory'
            CurrentValue = $global:VgmFixtureScenario.currentValue
            PossibleValues = @('512 MB', '4 GB', '8 GB', '16 GB', '32 GB', '48 GB')
            IsReadOnly = 0
            RequiresPhysicalPresence = 0
        }
    }
    if ($Namespace -notin @('root/cimv2', 'root\cimv2')) { throw "Unexpected namespace: $Namespace" }
    switch ($ClassName) {
        'Win32_ComputerSystem' {
            return [pscustomobject]@{
                Model = 'HP ZBook Ultra G1a 14 inch Mobile Workstation PC'
                TotalPhysicalMemory = 51303384350
            }
        }
        'Win32_PhysicalMemory' {
            foreach ($capacity in $global:VgmFixtureScenario.moduleCapacities) {
                [pscustomobject]@{ Capacity = $capacity }
            }
            return
        }
        'Win32_OperatingSystem' {
            return [pscustomobject]@{ TotalVisibleMemorySize = 50100961 }
        }
        default { throw "Unexpected CIM class: $ClassName" }
    }
}

# Guard the hardware boundary: a regression must never write BIOS or restart.
function global:Invoke-CimMethod { throw 'Mutation forbidden: Invoke-CimMethod' }
function global:Set-CimInstance { throw 'Mutation forbidden: Set-CimInstance' }
function global:Restart-Computer { throw 'Mutation forbidden: Restart-Computer' }
function global:Stop-Computer { throw 'Mutation forbidden: Stop-Computer' }

& $ScriptPath
exit $LASTEXITCODE
