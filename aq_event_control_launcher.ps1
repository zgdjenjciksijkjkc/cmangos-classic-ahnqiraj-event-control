param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('EnableCollection', 'EnableTransportation', 'EnableGong', 'EnableTenHourWar', 'Status', 'DisableAll')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$target = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' |
    Where-Object { $_.Name -ne 'aq_event_control_launcher.ps1' } |
    Where-Object {
        Select-String -LiteralPath $_.FullName -SimpleMatch `
            "ValidateSet('EnableCollection', 'EnableTransportation', 'EnableGong', 'EnableTenHourWar', 'Status', 'DisableAll')" -Quiet
    } |
    Select-Object -First 1

if (-not $target) {
    throw 'AQ control PowerShell script was not found.'
}

& $target.FullName -Action $Action
exit $LASTEXITCODE
