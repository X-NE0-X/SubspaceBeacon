$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'common.ps1')

try {
    if (-not (Test-IsAdmin)) { Fail-Orion 'Administrator privileges are required.' 10 }
    Write-OrionLog 'Deactivation starting.'

    if (-not (Test-Path $MarkerPath)) {
        Write-OrionLog 'No ORION Subspace Beacon marker exists. Nothing to remove.'
        exit 0
    }

    $userCreated = (Get-ManifestValue 'UserCreated') -eq '1'

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc -ne $null) {
        if ($svc.Status -ne 'Stopped') {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }
        & sc.exe delete $ServiceName | Out-Null
        Write-OrionLog "Removed service $ServiceName."
    }

    Remove-OrionFirewallRule
    Write-OrionLog 'Removed ORION Subspace Beacon firewall rule.'

    if ($userCreated) {
        Remove-RemoteUser
    }
    else {
        Write-OrionLog 'Manifest says the local account was not created by ORION; leaving it untouched.'
    }

    # All remaining files are under ORION's dedicated namespace.
    if (Test-Path $OrionRoot) {
        Start-Sleep -Milliseconds 500
        Remove-OrionTree $OrionRoot
        Write-OrionLog 'Removed C:\ProgramData\ORION.'
    }

    Write-Host ''
    Write-Host '=== ORION SUBSPACE BEACON DEACTIVATED ===' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host $_.Exception.ToString() -ForegroundColor Red
    exit $script:RequestedExitCode
}
