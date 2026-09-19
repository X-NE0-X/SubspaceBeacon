$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'common.ps1')

$freshEnrollment = -not (Test-Path $MarkerPath)
$interruptedInstallation = (Test-Path $MarkerPath) -and (Test-Path $InstallStatePath)
if ($interruptedInstallation) { $freshEnrollment = $true }
$userCreatedThisRun = $false
$serviceCreatedThisRun = $false
$serviceStoppedForRefreshThisRun = $false
$firewallCreatedThisRun = $false
$rootCreatedThisRun = $false
$orphanCleanupRequestedThisRun = $false

function Test-OrionHostKey([string]$SshKeygen, [string]$KeyPath) {
    if (-not (Test-Path -LiteralPath $KeyPath)) { return $false }
    try {
        $probe = Invoke-OrionProcess $SshKeygen ('-y -P "" -f "' + $KeyPath + '"')
        return ([int]$probe.ExitCode -eq 0)
    }
    catch { return $false }
}

function Get-OrionSshdProcesses([string]$ExecutablePath) {
    $fullPath = [System.IO.Path]::GetFullPath($ExecutablePath)
    try {
        return @(Get-WmiObject -Class Win32_Process -Filter "Name='sshd.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $candidatePath = [string]$_.ExecutablePath
            if ($candidatePath.Length -eq 0) { return $false }
            try {
                return [String]::Equals(
                    [System.IO.Path]::GetFullPath($candidatePath),
                    $fullPath,
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
            catch { return $false }
        })
    }
    catch { return @() }
}

function Wait-OrionSshdReleased([string]$ExecutablePath, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $processes = @(Get-OrionSshdProcesses $ExecutablePath)
        if ($processes.Count -eq 0) { return }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    $processes = @(Get-OrionSshdProcesses $ExecutablePath)
    foreach ($process in $processes) {
        Write-OrionLog ("Terminating lingering ORION sshd process {0} after service stop." -f $process.ProcessId)
        & taskkill.exe /PID ([string]$process.ProcessId) /T /F | Out-Null
    }
    Start-Sleep -Milliseconds 500
    if (@(Get-OrionSshdProcesses $ExecutablePath).Count -gt 0) {
        Fail-Orion ("ORION sshd process still holds files after service stop: {0}" -f $ExecutablePath) 30
    }
}

try {
    if (-not (Test-IsAdmin)) { Fail-Orion 'Administrator privileges are required.' 10 }

    $UsbRoot = Split-Path -Parent $ScriptDir
    $PublicKeyPath = Join-Path $UsbRoot 'identity\controller.pub'
    $Arch = Get-OsArch
    $Payload = Join-Path $UsbRoot ('payload\openssh\' + $Arch)

Write-OrionLog 'Compatibility build 20260918-NETSH-PROCESS-BOOL-OWNER-RESTORE-ROLLBACK-ACLORDER-PAYLOAD-HOSTKEY-EXACTACL-PS2ACL-NOREADBACK-OWNERCAST-VALIDATE-FIRST-ROUTE-AUTO-PRIVATE-LAN-IP-REPORT-SERVICE-STOP-BEFORE-REFRESH-SSHD-VALIDATE-DETAIL-EMPTY-HOSTKEY-PASSPHRASE-RECOVERY-LATE-MARKER-KEYGEN-PROCESS-ARGS-WIN32-SSH95-LEGACY-AUTHENTICATED-USERS-RX.'
    Write-OrionLog "Subspace Beacon starting on $env:COMPUTERNAME ($Arch)."

    if ($interruptedInstallation) {
        $orphanCleanupRequestedThisRun = $true
        Write-OrionLog 'Found an interrupted ORION installation; removing its stale service, account, and files before retry.'
        try {
            $staleService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($staleService -ne $null) {
                if ($staleService.Status -eq 'Running') { Stop-Service -Name $ServiceName -Force -ErrorAction Stop }
                & sc.exe delete $ServiceName | Out-Null
            }
        }
        catch { Fail-Orion ("Failed to remove the interrupted {0} service: {1}" -f $ServiceName, $_.Exception.Message) 29 }
        try { Remove-OrionFirewallRule } catch {}
        try { Remove-RemoteUser } catch { Fail-Orion ("Failed to remove the interrupted ORION account: {0}" -f $_.Exception.Message) 29 }
        if (Test-Path $OrionRoot) {
            Remove-OrionTree $OrionRoot
            if (Test-Path $OrionRoot) { Fail-Orion 'Failed to remove the interrupted C:\ProgramData\ORION installation.' 25 }
        }
    }

    if ($freshEnrollment -and (Test-Path $OrionRoot)) {
        if (Test-OrionPartialRoot) {
            $orphanCleanupRequestedThisRun = $true
            Write-OrionLog 'Found an incomplete ORION installation; removing it before retry.'
            Remove-OrionTree $OrionRoot
            if (Test-Path $OrionRoot) { Fail-Orion 'Failed to remove the incomplete C:\ProgramData\ORION installation.' 25 }
        }
        else {
            Fail-Orion 'C:\ProgramData\ORION already exists without an ORION Subspace Beacon marker. Refusing to modify it.' 25
        }
    }
    if ($freshEnrollment -and ((Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) -ne $null)) { Fail-Orion ("Service {0} already exists without an ORION Subspace Beacon marker. Refusing to modify it." -f $ServiceName) 26 }

    if (-not (Test-Path $PublicKeyPath)) { Fail-Orion 'identity\controller.pub is missing. Run PREPARE-KEY first.' 11 }
    $keys = @(Get-Content $PublicKeyPath | Where-Object { ($_ -ne $null) -and ($_.Trim().Length -gt 0) -and (-not $_.Trim().StartsWith('#')) })
    if (($keys.Count -eq 0) -or ($keys[0] -like 'REPLACE_ME*')) { Fail-Orion 'Controller public key is not prepared. Run PREPARE-KEY first.' 12 }
    foreach ($key in $keys) {
        $t = $key.Trim()
        if (($t -notlike 'ssh-* *') -and ($t -notlike 'ecdsa-* *') -and ($t -notlike 'sk-* *')) {
            Fail-Orion ("Unsupported or malformed public key line: {0}" -f $t) 13
        }
    }

    if (-not (Test-Path (Join-Path $Payload 'sshd.exe'))) {
        Fail-Orion ("Offline OpenSSH payload for {0} is missing from SUBSPACE BEACON." -f $Arch) 14
    }

    # Fresh install refuses to steal the fixed port from another process.
    if (-not (Test-Path $MarkerPath)) {
        $listening = & netstat.exe -ano -p tcp | Select-String (':{0}\s+.*LISTENING' -f $Port)
        if ($listening -ne $null) { Fail-Orion ("TCP port {0} is already in use. ORION will not replace another service." -f $Port) 15 }
    }

    $userCreatedResult = @(Ensure-RemoteUser)
    if ($userCreatedResult.Count -eq 0) { Fail-Orion 'Remote account provisioning returned no status.' 28 }
    $userCreated = [bool]$userCreatedResult[$userCreatedResult.Count - 1]
    $userCreatedThisRun = $userCreated

    if (-not (Test-Path $OrionRoot)) {
        New-Item -ItemType Directory -Path $OrionRoot -Force | Out-Null
        $rootCreatedThisRun = $true
        Write-Ascii $InstallStatePath "ORION Subspace Beacon installation in progress.`r`n"
    }
    Set-OrionAcl $OrionRoot $true
    if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
    Set-OrionAcl $InstallDir $true

    # An idempotent activation refreshes the isolated payload in place. Stop
    # the ORION service before Copy-Item so Win32-OpenSSH DLLs are not locked
    # by the running sshd process on Windows 7.
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (($existingService -ne $null) -and ($existingService.Status -eq 'Running')) {
        Write-OrionLog "Stopping existing service $ServiceName before payload refresh."
        Stop-Service -Name $ServiceName -Force -ErrorAction Stop
        $serviceStoppedForRefreshThisRun = $true
        $stopDeadline = (Get-Date).AddSeconds(15)
        do {
            Start-Sleep -Milliseconds 250
            $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        } while (($existingService -ne $null) -and ($existingService.Status -ne 'Stopped') -and ((Get-Date) -lt $stopDeadline))
        if (($existingService -ne $null) -and ($existingService.Status -ne 'Stopped')) {
            Fail-Orion ("Service {0} did not stop before payload refresh." -f $ServiceName) 30
        }
    }

    $sshd = Join-Path $InstallDir 'sshd.exe'
    Wait-OrionSshdReleased $sshd 15
    Write-OrionLog 'Copying isolated OpenSSH payload.'
    Copy-Item (Join-Path $Payload '*') $InstallDir -Recurse -Force
    # OpenSSH 9.8 split the Windows server into sshd.exe and
    # sshd-session.exe. On the Win7 x86 target that split resets the session
    # immediately after KEXINIT. The win32 payload is pinned to the last
    # pre-split 9.5 server, so remove any stale split-server binary left by an
    # earlier activation refresh.
    if ($Arch -eq 'win32') {
        $staleSession = Join-Path $InstallDir 'sshd-session.exe'
        if (Test-Path -LiteralPath $staleSession) {
            Remove-Item -LiteralPath $staleSession -Force -ErrorAction Stop
            Write-OrionLog 'Removed stale sshd-session.exe from the Win32-OpenSSH installation.'
        }
    }
    if (-not (Test-Path (Join-Path $InstallDir 'sshd.exe'))) { Fail-Orion 'sshd.exe was not copied successfully.' 16 }
    $remoteAcl = ('{0}\{1}:(RX)' -f $env:COMPUTERNAME, $RemoteUser)
    $remoteTreeAcl = ('{0}\{1}:(OI)(CI)RX' -f $env:COMPUTERNAME, $RemoteUser)
    $workerTreeAcl = '*S-1-5-11:(OI)(CI)RX'
    & icacls.exe $OrionRoot '/grant:r' $remoteAcl | Out-Null
    & icacls.exe $InstallDir '/grant:r' $remoteTreeAcl $workerTreeAcl '/T' | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail-Orion 'Failed to grant OpenSSH worker read/execute access.' 29 }

    $keyText = ($keys | ForEach-Object { $_.Trim() }) -join "`r`n"
    Write-Ascii $AuthorizedKeysPath ($keyText + "`r`n")
    Set-OrionAcl $AuthorizedKeysPath $false

    $keyDir = Join-Path $OrionRoot 'hostkeys'
    $sshKeygen = Join-Path $InstallDir 'ssh-keygen.exe'
    $edKey = Join-Path $keyDir 'ssh_host_ed25519_key'
    $rsaKey = Join-Path $keyDir 'ssh_host_rsa_key'
    if (-not (Test-Path -LiteralPath $keyDir)) { New-Item -ItemType Directory -Path $keyDir -Force | Out-Null }
    Set-OrionAcl $keyDir $true
    $generateEdKey = -not (Test-Path -LiteralPath $edKey)
    if ((-not $generateEdKey) -and (-not (Test-OrionHostKey $sshKeygen $edKey))) {
        Write-OrionLog 'Existing ED25519 host key is not readable with an empty passphrase; regenerating the ORION-managed key.'
        Remove-Item -LiteralPath $edKey -Force -ErrorAction Stop
        if (Test-Path -LiteralPath ($edKey + '.pub')) { Remove-Item -LiteralPath ($edKey + '.pub') -Force -ErrorAction Stop }
        $generateEdKey = $true
    }
    if ($generateEdKey) {
        Write-OrionLog 'Generating ED25519 host key.'
        $edKeygen = Invoke-OrionProcess $sshKeygen ('-q -t ed25519 -f "' + $edKey + '" -N ""')
        if ([int]$edKeygen.ExitCode -ne 0) {
            Fail-Orion ("Failed to generate ED25519 host key. {0}" -f $edKeygen.Output) 17
        }
    }
    $generateRsaKey = -not (Test-Path -LiteralPath $rsaKey)
    if ((-not $generateRsaKey) -and (-not (Test-OrionHostKey $sshKeygen $rsaKey))) {
        Write-OrionLog 'Existing RSA host key is not readable with an empty passphrase; regenerating the ORION-managed key.'
        Remove-Item -LiteralPath $rsaKey -Force -ErrorAction Stop
        if (Test-Path -LiteralPath ($rsaKey + '.pub')) { Remove-Item -LiteralPath ($rsaKey + '.pub') -Force -ErrorAction Stop }
        $generateRsaKey = $true
    }
    if ($generateRsaKey) {
        Write-OrionLog 'Generating RSA host key.'
        $rsaKeygen = Invoke-OrionProcess $sshKeygen ('-q -t rsa -b 3072 -f "' + $rsaKey + '" -N ""')
        if ([int]$rsaKeygen.ExitCode -ne 0) {
            Fail-Orion ("Failed to generate RSA host key. {0}" -f $rsaKeygen.Output) 18
        }
    }
    Set-OrionAcl $keyDir $true
    foreach ($publicKeyFile in @(($edKey + '.pub'), ($rsaKey + '.pub'))) {
        if (Test-Path -LiteralPath $publicKeyFile) { Set-OrionAcl $publicKeyFile $false }
    }

    $cfg = @"
Port $Port
AddressFamily any
ListenAddress 0.0.0.0
HostKey C:/ProgramData/ORION/hostkeys/ssh_host_ed25519_key
HostKey C:/ProgramData/ORION/hostkeys/ssh_host_rsa_key
PubkeyAuthentication yes
PasswordAuthentication no
AuthenticationMethods publickey
PermitEmptyPasswords no
AuthorizedKeysFile C:/ProgramData/ORION/authorized_keys
AllowUsers $RemoteUser
AllowTcpForwarding no
PermitTTY yes
Subsystem sftp C:/ProgramData/ORION/OpenSSH/sftp-server.exe
LogLevel VERBOSE
"@
    Write-Ascii $ConfigPath $cfg
    Set-OrionAcl $ConfigPath $false

    # Validate while the activating administrator can still read the generated
    # host keys. The service itself runs as LocalSystem and reads the hardened
    # SYSTEM-only files below.
    $validation = Invoke-OrionProcess $sshd ('-t -f "' + $ConfigPath + '"')
    if ([int]$validation.ExitCode -ne 0) {
        $validationDetail = ([string]$validation.Output).Trim()
        if ($validationDetail.Length -eq 0) {
            $validationDetail = ('sshd -t returned exit code {0} without diagnostic output.' -f $validation.ExitCode)
        }
        if ($validationDetail.Length -gt 1600) { $validationDetail = $validationDetail.Substring(0, 1600) }
        Fail-Orion ("OpenSSH rejected the generated configuration. sshd -t output: {0}" -f $validationDetail) 19
    }

    foreach ($privateKeyFile in @($edKey, $rsaKey)) {
        if (Test-Path -LiteralPath $privateKeyFile) { Set-OrionPrivateKeyAcl $privateKeyFile }
    }

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service -eq $null) {
        $binPath = '"' + $sshd + '" -f "' + $ConfigPath + '" -E "' + $LogPath + '"'
        $svcClass = [WMIClass]'Win32_Service'
        $result = $svcClass.Create($ServiceName, $ServiceDisplayName, $binPath, 16, 1, 'Automatic', $false, 'LocalSystem', $null, $null, $null, $null)
        if (($result -eq $null) -or ($result.ReturnValue -ne 0)) {
            Fail-Orion ("Failed to create service {0}. WMI return code: {1}" -f $ServiceName, $result.ReturnValue) 20
        }
        & sc.exe privs $ServiceName 'SeAssignPrimaryTokenPrivilege/SeTcbPrivilege/SeBackupPrivilege/SeRestorePrivilege/SeImpersonatePrivilege' | Out-Null
        $serviceCreatedThisRun = $true
        Write-OrionLog "Created service $ServiceName."
    }
    else {
        Write-OrionLog "Reusing service $ServiceName."
        if ($service.Status -eq 'Running') { Stop-Service -Name $ServiceName -Force }
    }

    # Restrict the endpoint to local and RFC1918 private-LAN inbound traffic.
    Write-OrionLog 'Creating local-subnet and private-LAN firewall rules.'
    Add-OrionFirewallRule
    $firewallCreatedThisRun = $true

    $deviceId = [Guid]::NewGuid().ToString('N')
    if (Test-Path $EndpointPath) {
        try {
            $old = [System.IO.File]::ReadAllText($EndpointPath)
            $m = [Regex]::Match($old, '"device_id"\s*:\s*"([^"]+)"')
            if ($m.Success) { $deviceId = $m.Groups[1].Value }
        }
        catch {}
    }
    $os = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -First 1
    $endpointJson = "{`r`n" +
    ('  "orion_endpoint": true,' + "`r`n") +
    ('  "version": 1,' + "`r`n") +
    ('  "device_id": "' + (Json-Escape $deviceId) + '",' + "`r`n") +
    ('  "hostname": "' + (Json-Escape $env:COMPUTERNAME) + '",' + "`r`n") +
    ('  "user": "' + (Json-Escape $RemoteUser) + '",' + "`r`n") +
    ('  "port": ' + $Port + ',' + "`r`n") +
    ('  "architecture": "' + (Json-Escape $Arch) + '",' + "`r`n") +
    ('  "windows": "' + (Json-Escape $os.Caption) + '",' + "`r`n") +
    ('  "enrolled_at_utc": "' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') + '"' + "`r`n") +
    "}`r`n"
    Write-Utf8NoBom $EndpointPath $endpointJson
    Set-OrionAcl $EndpointPath $false
    $endpointReadAcl = ('{0}\{1}:R' -f $env:COMPUTERNAME, $RemoteUser)
    & icacls.exe $EndpointPath '/grant:r' $endpointReadAcl | Out-Null

    try {
        Start-Service -Name $ServiceName
    }
    catch {
        $serviceError = $_.Exception.Message
        $logDetail = ''
        if (Test-Path $LogPath) {
            try {
                $logDetail = [System.IO.File]::ReadAllText($LogPath)
                if ($logDetail.Length -gt 1600) { $logDetail = $logDetail.Substring($logDetail.Length - 1600) }
            }
            catch {}
        }
        if ($logDetail.Length -gt 0) {
            throw ("Service {0} failed to start: {1}`r`nsshd.log tail:`r`n{2}" -f $ServiceName, $serviceError, $logDetail)
        }
        throw ("Service {0} failed to start: {1}" -f $ServiceName, $serviceError)
    }
    Start-Sleep -Seconds 1
    $service = Get-Service -Name $ServiceName
    if ($service.Status -ne 'Running') { Fail-Orion 'SUBSPACERELAY did not reach Running state. Check C:\ProgramData\ORION\sshd.log.' 24 }

    # The marker is the commit point for activation. Write it only after the
    # service is running and endpoint metadata is complete, so a failed start
    # cannot leave an apparently healthy installation behind.
    Write-Ascii $MarkerPath "ORION Subspace Beacon Key v1`r`n"
    Write-Manifest $userCreated
    Set-OrionAcl $ManifestPath $false

    if (Test-Path -LiteralPath $InstallStatePath) {
        Remove-Item -LiteralPath $InstallStatePath -Force -ErrorAction Stop
    }

    Write-OrionLog 'Subspace Beacon deployed.'
    Write-Host ''
    Write-Host '=== ORION ENDPOINT ONLINE ===' -ForegroundColor Green
    Write-Host ("Hostname : {0}" -f $env:COMPUTERNAME)
    Write-Host ("User     : {0}" -f $RemoteUser)
    Write-Host ("Port     : {0}" -f $Port)
    Write-Host ("Device ID: {0}" -f $deviceId)
    Write-Host 'Scope    : Local Subnet plus RFC1918 private LAN ranges'
    Write-OrionNetworkReport
    Write-Host ''
    Write-Host 'Controller: run controller/discover.py with the private key.'
    exit 0
}
catch {
    $failure = $_.Exception.ToString()
    if ($freshEnrollment) {
        Write-OrionLog 'Fresh Subspace Beacon failed; attempting rollback of ORION-owned changes.'
        try {
            $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($svc -ne $null) {
                Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
                & sc.exe delete $ServiceName | Out-Null
            }
        }
        catch {}
        try { Remove-OrionFirewallRule } catch {}
        if ($userCreatedThisRun) {
            try { Remove-RemoteUser } catch {}
        }
        if (($rootCreatedThisRun -or $orphanCleanupRequestedThisRun) -and (Test-Path $OrionRoot)) {
            try {
                Remove-OrionTree $OrionRoot
                Write-OrionLog 'Rollback removed C:\ProgramData\ORION.'
            }
            catch {
                Write-OrionLog ("Rollback cleanup failed: {0}" -f $_.Exception.Message)
            }
        }
    }
    else {
        # Best effort: restore the service only when this run stopped it.
        if ($serviceStoppedForRefreshThisRun) {
            try {
                $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
                if (($svc -ne $null) -and ($svc.Status -ne 'Running')) { Start-Service -Name $ServiceName -ErrorAction SilentlyContinue }
            }
            catch {}
        }
    }
    Write-Host $failure -ForegroundColor Red
    try { Write-Host ("Failure location: " + $_.InvocationInfo.PositionMessage) -ForegroundColor Yellow } catch {}
    exit $script:RequestedExitCode
}
