# PowerShell 2.0 compatible helpers for ORION Subspace Beacon Key v1.

$script:OrionRoot = 'C:\ProgramData\ORION'
$script:InstallDir = Join-Path $script:OrionRoot 'OpenSSH'
$script:ConfigPath = Join-Path $script:OrionRoot 'sshd_config'
$script:AuthorizedKeysPath = Join-Path $script:OrionRoot 'authorized_keys'
$script:EndpointPath = Join-Path $script:OrionRoot 'endpoint.json'
$script:ManifestPath = Join-Path $script:OrionRoot 'manifest.ini'
$script:LogPath = Join-Path $script:OrionRoot 'sshd.log'
$script:ServiceName = 'SUBSPACERELAY'
$script:ServiceDisplayName = 'ORION Subspace Relay Beacon'
$script:FirewallRule = 'ORION-SSH-22022'
$script:FirewallPrivateRule = 'ORION-SSH-22022-PRIVATE-LAN'
$script:FirewallPrivateRanges = '10.0.0.0/8,172.16.0.0/12,192.168.0.0/16'
$script:RemoteUser = 'ORION-RELAY'
$script:Port = 22022
$script:MarkerPath = Join-Path $script:OrionRoot '.orion-subspace-beacon-v1'
$script:InstallStatePath = Join-Path $script:OrionRoot '.orion-subspace-beacon-installing-v1'
$script:RequestedExitCode = 99

function Write-OrionLog([string]$Message) {
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host ("[ORION {0}] {1}" -f $stamp, $Message)
}

function Get-OrionPrivateIPv4 {
    $rows = @()
    try {
        $configs = @(Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -ErrorAction Stop)
        foreach ($config in $configs) {
            $description = [string]$config.Description
            foreach ($address in @($config.IPAddress)) {
                $text = [string]$address
                if ($text -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { continue }
                if (($text -like '127.*') -or ($text -like '169.254.*')) { continue }
                $duplicate = $false
                foreach ($row in $rows) {
                    if ([string]$row.Address -eq $text) { $duplicate = $true; break }
                }
                if (-not $duplicate) {
                    $rows += (New-Object PSObject -Property @{ Address = $text; Adapter = $description })
                }
            }
        }
    }
    catch {}
    return $rows
}

function Get-OrionPublicIPv4 {
    $urls = @('https://api.ipify.org', 'https://ifconfig.me/ip')
    # .NET 4.x on older Windows may not enable TLS 1.2 by default.
    try { [System.Net.ServicePointManager]::SecurityProtocol = 3072 } catch {}
    foreach ($url in $urls) {
        $response = $null
        $reader = $null
        try {
            $request = [System.Net.WebRequest]::Create($url)
            $request.Method = 'GET'
            $request.Timeout = 2500
            $response = $request.GetResponse()
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $value = $reader.ReadToEnd().Trim()
            if ($value -match '^\d{1,3}(\.\d{1,3}){3}$') {
                $parsed = [System.Net.IPAddress]::Parse($value)
                if ($parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                    return $value
                }
            }
        }
        catch {}
        finally {
            if ($reader -ne $null) { try { $reader.Close() } catch {} }
            if ($response -ne $null) { try { $response.Close() } catch {} }
        }
    }
    return ''
}

function Test-OrionRfc1918IPv4([string]$Text) {
    return (($Text -match '^10\.') -or ($Text -match '^172\.(1[6-9]|2[0-9]|3[01])\.') -or ($Text -match '^192\.168\.'))
}

function Write-OrionNetworkReport {
    Write-Host ''
    Write-Host '=== ORION NETWORK ADDRESSES ===' -ForegroundColor Cyan
    $allLocalAddresses = @(Get-OrionPrivateIPv4)
    $privateAddresses = @()
    $otherLocalAddresses = @()
    foreach ($row in $allLocalAddresses) {
        if (Test-OrionRfc1918IPv4 ([string]$row.Address)) {
            $privateAddresses += $row
        }
        else {
            $otherLocalAddresses += $row
        }
    }
    if ($privateAddresses.Count -eq 0) {
        Write-Host 'Private IPv4: unavailable'
    }
    else {
        foreach ($row in $privateAddresses) {
            Write-Host ("Private IPv4: {0} [{1}]" -f $row.Address, $row.Adapter)
        }
    }
    foreach ($row in $otherLocalAddresses) {
        Write-Host ("Other local IPv4: {0} [{1}]" -f $row.Address, $row.Adapter)
    }
    $publicAddress = Get-OrionPublicIPv4
    if ([string]::IsNullOrEmpty([string]$publicAddress)) {
        Write-Host 'Public IPv4 : unavailable (offline or lookup blocked)'
    }
    else {
        Write-Host ("Public IPv4 : {0}" -f $publicAddress)
    }
    Write-Host '================================'
    Write-Host ''
}

function Fail-Orion([string]$Message, [int]$Code) {
    $script:RequestedExitCode = $Code
    throw $Message
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Write-Ascii([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::ASCII)
}

function Json-Escape([string]$Text) {
    if ($Text -eq $null) { return '' }
    return $Text.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", '\n')
}

function Get-OsArch {
    # Detect native OS architecture, including WOW64 and Windows on ARM.
    $pa = [string]$env:PROCESSOR_ARCHITECTURE
    $paw = [string]$env:PROCESSOR_ARCHITEW6432

    if (($pa -ieq 'ARM64') -or ($paw -ieq 'ARM64')) { return 'arm64' }
    if (($pa -ieq 'AMD64') -or ($paw -ieq 'AMD64') -or (Test-Path "$env:WINDIR\SysWOW64")) { return 'win64' }
    return 'win32'
}

function Get-SecureRandomPassword([int]$Length) {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] $Length
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    # Legacy .NET/PowerShell builds may expose neither Dispose nor IDisposable
    # for this provider. The short-lived activation process owns this instance;
    # let the runtime finalize it after the password bytes are generated.
    $rng.GetBytes($bytes)
    $rng = $null
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Length; $i++) {
        [void]$sb.Append($chars[$bytes[$i] % $chars.Length])
    }
    return $sb.ToString()
}

function Test-LocalUser([string]$Name) {
    try {
        $escapedName = $Name.Replace("'", "''")
        $filter = "LocalAccount=True AND Name='$escapedName'"
        $accounts = @(Get-WmiObject -Class Win32_UserAccount -Filter $filter -ErrorAction Stop)
        foreach ($account in $accounts) {
            if (($account.LocalAccount -eq $true) -and ($account.Name -ieq $Name)) {
                return $true
            }
        }
        return $false
    }
    catch {
        throw ("Failed to query local account {0}: {1}" -f $Name, $_.Exception.Message)
    }
}

function Ensure-RemoteUser {
    if (Test-LocalUser $script:RemoteUser) {
        if (-not (Test-Path $script:MarkerPath)) {
            Fail-Orion "Local user $($script:RemoteUser) already exists but was not created by ORION. Refusing to modify it." 21
        }
        Write-OrionLog "Reusing existing ORION-managed account $($script:RemoteUser)."
        return $false
    }

    $password = Get-SecureRandomPassword 40
    $computer = [ADSI]("WinNT://{0},computer" -f $env:COMPUTERNAME)
    $user = $computer.Create('user', $script:RemoteUser)
    $null = $user.SetPassword($password)
    $null = $user.Put('Description', 'Temporary ORION LAN SSH management account')
    $null = $user.SetInfo()
    try {
        $flags = [int]$user.UserFlags.Value
        $null = $user.Put('UserFlags', ($flags -bor 0x10000)) # ADS_UF_DONT_EXPIRE_PASSWD
        $null = $user.SetInfo()
    }
    catch {}

    $adminGroup = Get-WmiObject -Class Win32_Group -Filter "SID='S-1-5-32-544'" | Select-Object -First 1
    if ($adminGroup -eq $null) { Fail-Orion 'Could not resolve the local Administrators group by SID.' 22 }
    $group = [ADSI]("WinNT://./{0},group" -f $adminGroup.Name)
    $isMember = $false
    try {
        $members = @($group.psbase.Invoke('Members'))
        foreach ($member in $members) {
            $memberName = $member.GetType().InvokeMember('Name', 'GetProperty', $null, $member, $null)
            if ($memberName -ieq $script:RemoteUser) { $isMember = $true; break }
        }
    }
    catch {}
    if (-not $isMember) {
        $null = $group.Add(("WinNT://{0}/{1},user" -f $env:COMPUTERNAME, $script:RemoteUser))
        $members = @($group.psbase.Invoke('Members'))
        foreach ($member in $members) {
            $memberName = $member.GetType().InvokeMember('Name', 'GetProperty', $null, $member, $null)
            if ($memberName -ieq $script:RemoteUser) { $isMember = $true; break }
        }
    }
    if (-not $isMember) { Fail-Orion 'Failed to add the ORION account to the local Administrators group.' 27 }
    Write-OrionLog "Created local administrator account $($script:RemoteUser) with a random non-exported password."
    return $true
}

function Remove-RemoteUser {
    if (-not (Test-LocalUser $script:RemoteUser)) { return }
    $computer = [ADSI]("WinNT://{0},computer" -f $env:COMPUTERNAME)
    $null = $computer.Delete('user', $script:RemoteUser)
    Write-OrionLog "Removed local account $($script:RemoteUser)."
}

function Invoke-OrionProcess([string]$FileName, [string]$Arguments) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FileName
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $output = (($stdout + ' ' + $stderr).Trim())
    return (New-Object PSObject -Property @{ ExitCode = [int]$process.ExitCode; Output = $output })
}

function Remove-OrionFirewallRule {
    # Remove both modern rules and the legacy port object.
    $netshPath = $env:WINDIR + '\System32\netsh.exe'
    try { $null = Invoke-OrionProcess $netshPath ('advfirewall firewall delete rule name=' + $script:FirewallRule) } catch {}
    try { $null = Invoke-OrionProcess $netshPath ('advfirewall firewall delete rule name=' + $script:FirewallPrivateRule) } catch {}
    try { $null = Invoke-OrionProcess $netshPath ('firewall delete portopening protocol=TCP port=' + $script:Port) } catch {}
}

function Add-OrionFirewallRule {
    Remove-OrionFirewallRule

    # Some older images have the firewall service stopped even though the
    # firewall command context is installed. Start it through sc.exe without
    # passing native command arguments through PowerShell's binder.
    $scPath = $env:WINDIR + '\System32\sc.exe'
    try {
        $null = Invoke-OrionProcess $scPath 'config MpsSvc start= auto'
        $null = Invoke-OrionProcess $scPath 'start MpsSvc'
        [System.Threading.Thread]::Sleep(1000)
    }
    catch {}

    $netshPath = $env:WINDIR + '\System32\netsh.exe'
    # LocalSubnet is correct for a flat LAN, but older routers may put the
    # 2.4 GHz and 5 GHz clients in separate RFC1918 subnets. Keep the normal
    # rule and add a private-LAN rule so DHCP changes do not require edits.
    $localArgs = 'advfirewall firewall add rule name=' + $script:FirewallRule + ' dir=in action=allow enable=yes profile=any protocol=tcp localport=' + $script:Port + ' remoteip=localsubnet'
    $privateArgs = 'advfirewall firewall add rule name=' + $script:FirewallPrivateRule + ' dir=in action=allow enable=yes profile=any protocol=tcp localport=' + $script:Port + ' remoteip=' + $script:FirewallPrivateRanges
    $localResult = Invoke-OrionProcess $netshPath $localArgs
    $privateResult = Invoke-OrionProcess $netshPath $privateArgs
    $localExit = [int]$localResult.ExitCode
    $privateExit = [int]$privateResult.ExitCode
    if (($localExit -eq 0) -or ($privateExit -eq 0)) { return }

    # Windows 7 also retains the older netsh firewall helper. Keep the active
    # profile so this works even when the target is using the Public profile.
    $legacyArgs = 'firewall add portopening TCP ' + $script:Port + ' ' + $script:FirewallRule + ' mode=ENABLE scope=CUSTOM addresses=LocalSubnet profile=CURRENT'
    $legacyResult = Invoke-OrionProcess $netshPath $legacyArgs
    $legacyExit = [int]$legacyResult.ExitCode
    if ($legacyExit -eq 0) { return }

    $localDetail = [string]$localResult.Output
    if ($localDetail.Length -gt 240) { $localDetail = $localDetail.Substring(0, 240) }
    $privateDetail = [string]$privateResult.Output
    if ($privateDetail.Length -gt 240) { $privateDetail = $privateDetail.Substring(0, 240) }
    $legacyDetail = [string]$legacyResult.Output
    if ($legacyDetail.Length -gt 240) { $legacyDetail = $legacyDetail.Substring(0, 240) }
    Fail-Orion ("Failed to create LAN firewall rules. local exit={0}; local={1}; private exit={2}; private={3}; legacy exit={4}; legacy={5}" -f $localExit, $localDetail, $privateExit, $privateDetail, $legacyExit, $legacyDetail) 23
}

 $orionPrivilegeDefinition = @'
using System;
using System.Runtime.InteropServices;

public class OrionAdjPriv
{
    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall,
        ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    internal static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    internal static extern bool CloseHandle(IntPtr hObject);
    [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
    internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
    [DllImport("advapi32.dll", SetLastError = true)]
    internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    internal struct TokPriv1Luid
    {
        public int Count;
        public long Luid;
        public int Attr;
    }

    internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
    internal const int TOKEN_QUERY = 0x00000008;
    internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;

    public static bool EnablePrivilege(string privilege)
    {
        TokPriv1Luid tp;
        IntPtr htok = IntPtr.Zero;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok))
        {
            return false;
        }
        try
        {
            tp.Count = 1;
            tp.Luid = 0;
            tp.Attr = SE_PRIVILEGE_ENABLED;
            if (!LookupPrivilegeValue(null, privilege, ref tp.Luid))
            {
                return false;
            }
            if (!AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero))
            {
                return false;
            }
            return Marshal.GetLastWin32Error() == 0;
        }
        finally
        {
            CloseHandle(htok);
        }
    }
}
'@
$script:OrionPrivilegeType = $null

function Enable-OrionSeRestorePrivilege {
    if ($script:OrionPrivilegeType -eq $null) {
        try {
            $script:OrionPrivilegeType = @(Add-Type $orionPrivilegeDefinition -PassThru -ErrorAction Stop)
        }
        catch {
            try { $script:OrionPrivilegeType = @([OrionAdjPriv]) }
            catch { Fail-Orion 'Could not load the Windows privilege helper.' 29 }
        }
    }
    if (-not $script:OrionPrivilegeType[0]::EnablePrivilege('SeRestorePrivilege')) {
        Fail-Orion 'Failed to enable SeRestorePrivilege.' 29
    }
}

function Set-OrionOwner([string]$Path) {
    Enable-OrionSeRestorePrivilege
    $firstError = ''
    try {
        $acl = Get-Acl -Path $Path
        $systemSid = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-18'
        $owner = $systemSid.Translate([System.Security.Principal.NTAccount])
        $acl.SetOwner($owner)
        Set-Acl -Path $Path -AclObject $acl -Confirm:$false -ErrorAction Stop | Out-Null
        return
    }
    catch {
        $firstError = $_.Exception.Message
    }

    # Win7 can reject the .NET ACL write even with SeRestorePrivilege enabled.
    # Retry the native owner operation while the inherited ACL is still present.
    $icaclsPath = Join-Path $env:WINDIR 'System32\icacls.exe'
    $fallback = Invoke-OrionProcess $icaclsPath ('"' + $Path + '" /setowner *S-1-5-18')
    if ($fallback.ExitCode -ne 0) {
        Fail-Orion ("Failed to set SYSTEM as owner of {0}: .NET={1}; icacls exit={2}; icacls={3}" -f $Path, $firstError, $fallback.ExitCode, $fallback.Output) 29
    }
}

function Repair-OrionRemovalAcl([string]$Path) {
    $takeownPath = Join-Path $env:WINDIR 'System32\takeown.exe'
    $icaclsPath = Join-Path $env:WINDIR 'System32\icacls.exe'
    $takeown = Invoke-OrionProcess $takeownPath ('/F "' + $Path + '" /R /D Y')
    $reset = Invoke-OrionProcess $icaclsPath ('"' + $Path + '" /reset /T /C')
    $grant = Invoke-OrionProcess $icaclsPath ('"' + $Path + '" /grant:r *S-1-5-32-544:(OI)(CI)F /T /C')
    if ($grant.ExitCode -ne 0) {
        throw ("Could not repair removal permissions for {0}. takeown exit={1}; reset exit={2}; grant exit={3}; grant output={4}" -f $Path, $takeown.ExitCode, $reset.ExitCode, $grant.ExitCode, $grant.Output)
    }
}

function Remove-OrionTree([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return
    }
    catch {
        $firstError = $_.Exception.Message
    }

    $repairError = ''
    try { Repair-OrionRemovalAcl $Path }
    catch { $repairError = $_.Exception.Message }

    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
    catch {
        throw ("Failed to remove {0}. Initial error: {1}; ACL repair: {2}; final error: {3}" -f $Path, $firstError, $repairError, $_.Exception.Message)
    }
}

function Test-OrionPartialRoot {
    if (-not (Test-Path -LiteralPath $script:OrionRoot -PathType Container)) { return $false }
    if (Test-Path -LiteralPath $script:MarkerPath) { return $false }

    $children = $null
    try { $children = @(Get-ChildItem -LiteralPath $script:OrionRoot -Force -ErrorAction Stop) }
    catch {
        try { Repair-OrionRemovalAcl $script:OrionRoot }
        catch { return $false }
        try { $children = @(Get-ChildItem -LiteralPath $script:OrionRoot -Force -ErrorAction Stop) }
        catch { return $false }
    }

    $allowedNames = @(
        '.orion-subspace-beacon-installing-v1',
        'OpenSSH',
        'hostkeys',
        'authorized_keys',
        'sshd_config',
        'endpoint.json',
        'manifest.ini',
        'sshd.log'
    )
    foreach ($child in $children) {
        if ($allowedNames -notcontains $child.Name) { return $false }
    }
    return $true
}

function Set-OrionAcl([string]$Path, [bool]$Directory) {
    if ($Directory) {
        # Win32-OpenSSH creates an unprivileged pre-auth worker.  Win7 needs
        # Authenticated Users to be able to traverse/read the install tree.
        & icacls.exe $Path '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-11:(OI)(CI)RX' | Out-Null
    }
    else {
        # These files contain public configuration/key material.  Private
        # host keys are hardened separately by Set-OrionPrivateKeyAcl.
        & icacls.exe $Path '/grant:r' '*S-1-5-18:F' '*S-1-5-32-544:F' '*S-1-5-11:R' | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { Fail-Orion ("Failed to grant ORION permissions on {0}." -f $Path) 29 }
    Set-OrionOwner $Path
    & icacls.exe $Path '/inheritance:r' | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail-Orion ("Failed to remove inherited permissions from {0}." -f $Path) 29 }
}

function Set-OrionPrivateKeyAcl([string]$Path) {
    # OpenSSH rejects private host keys readable by any account other than SYSTEM.
    # Rebuild the DACL instead of editing a few inherited ACEs. Win7 can retain
    # the creator's explicit Administrator ACE after an inheritance conversion.
    Enable-OrionSeRestorePrivilege
    $systemSid = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-18'
    $firstError = ''
    $aclWritten = $false
    try {
        # PowerShell 2.0 on Windows 7 has no -LiteralPath on Get-Acl/Set-Acl.
        # This path is generated internally and contains no wildcard characters.
        $acl = Get-Acl -Path $Path
        $acl.SetAccessRuleProtection($true, $false)
        $existingRules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
        foreach ($existingRule in $existingRules) {
            [void]$acl.RemoveAccessRuleSpecific($existingRule)
        }
        $systemRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $systemSid, 'FullControl', 'Allow'
        [void]$acl.AddAccessRule($systemRule)
        $acl.SetOwner($systemSid)
        if (-not $acl.AreAccessRulesProtected) {
            throw 'planned private-key ACL still inherits permissions'
        }
        $plannedOwnerAccount = New-Object -TypeName System.Security.Principal.NTAccount -ArgumentList ([string]$acl.Owner)
        $plannedOwnerSid = $plannedOwnerAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
        if ($plannedOwnerSid -ne 'S-1-5-18') {
            throw ("planned private-key owner is {0}" -f $plannedOwnerSid)
        }
        $plannedRules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
        foreach ($plannedRule in $plannedRules) {
            if ($plannedRule.IdentityReference.Value -ne 'S-1-5-18') {
                throw ("planned private-key ACL contains {0}" -f $plannedRule.IdentityReference.Value)
            }
            if ($plannedRule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) {
                throw 'planned private-key ACL contains a deny rule'
            }
        }
        Set-Acl -Path $Path -AclObject $acl -Confirm:$false -ErrorAction Stop | Out-Null
        $aclWritten = $true
    }
    catch {
        $firstError = $_.Exception.Message
    }

    if (-not $aclWritten) {
        # Native fallback for old PowerShell/.NET ACL providers.
        $icaclsPath = Join-Path $env:WINDIR 'System32\icacls.exe'
        $reset = Invoke-OrionProcess $icaclsPath ('"' + $Path + '" /reset')
        $inheritance = Invoke-OrionProcess $icaclsPath ('"' + $Path + '" /inheritance:r')
        $owner = Invoke-OrionProcess $icaclsPath ('"' + $Path + '" /setowner *S-1-5-18')
        $grant = Invoke-OrionProcess $icaclsPath ('"' + $Path + '" /grant:r *S-1-5-18:F')
        if (($reset.ExitCode -ne 0) -or ($inheritance.ExitCode -ne 0) -or ($grant.ExitCode -ne 0) -or ($owner.ExitCode -ne 0)) {
            Fail-Orion ("Failed to harden private key {0}: .NET={1}; reset={2}; inheritance={3}; grant={4}; owner={5}" -f $Path, $firstError, $reset.ExitCode, $inheritance.ExitCode, $grant.ExitCode, $owner.ExitCode) 29
        }
    }

    # Do not read the file back here. After the exact ACL is applied, the
    # elevated Administrator intentionally loses READ_CONTROL; SYSTEM owns it.
}

function Get-ManifestValue([string]$Key) {
    if (-not (Test-Path $script:ManifestPath)) { return $null }
    $line = Get-Content $script:ManifestPath | Where-Object { $_ -like ($Key + '=*') } | Select-Object -First 1
    if ($line -eq $null) { return $null }
    return $line.Substring($Key.Length + 1)
}

function Write-Manifest([bool]$UserCreated) {
    $existingUserCreated = Get-ManifestValue 'UserCreated'
    if ($existingUserCreated -eq '1') { $UserCreated = $true }
    $text = @(
        'Version=1',
        ('UserCreated=' + $(if ($UserCreated) { '1' } else { '0' })),
        'ServiceCreated=1',
        'FirewallRuleCreated=1',
        ('Port=' + $script:Port),
        ('RemoteUser=' + $script:RemoteUser),
        ('EnrolledAt=' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
    ) -join "`r`n"
    Write-Ascii $script:ManifestPath ($text + "`r`n")
}
