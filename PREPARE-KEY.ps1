param(
    [string]$KeyName = "orion_enrollment_ed25519",
    [switch]$ForceNewKey
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Write-Step([string]$Message) {
    Write-Host "[ORION] $Message" -ForegroundColor Cyan
}

function Fail([string]$Message) {
    Write-Host "[ORION] ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Get-NativeArch {
    $pa = [string]$env:PROCESSOR_ARCHITECTURE
    $paw = [string]$env:PROCESSOR_ARCHITEW6432

    if (($pa -ieq "ARM64") -or ($paw -ieq "ARM64")) { return "arm64" }
    if (($pa -ieq "AMD64") -or ($paw -ieq "AMD64") -or (Test-Path "$env:WINDIR\SysWOW64")) { return "win64" }
    return "win32"
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$IdentityDir = Join-Path $ScriptDir "identity"
$PayloadRoot = Join-Path $ScriptDir "payload\openssh"

if (-not (Test-Path $IdentityDir)) {
    New-Item -ItemType Directory -Path $IdentityDir | Out-Null
}

# Verify every offline target payload exists.
foreach ($arch in @("win32", "win64", "arm64")) {
    $sshd = Join-Path (Join-Path $PayloadRoot $arch) "sshd.exe"
    $keygen = Join-Path (Join-Path $PayloadRoot $arch) "ssh-keygen.exe"
    if (-not (Test-Path $sshd)) {
        Fail ("Offline OpenSSH payload missing for {0}: {1}" -f $arch, $sshd)
    }
    if (-not (Test-Path $keygen)) {
        Fail ("Offline ssh-keygen payload missing for {0}: {1}" -f $arch, $keygen)
    }
}
Write-Step "Verified offline payloads: x86, x64, ARM64."

# Use SUBSPACE BEACON's own ssh-keygen. The controller Windows does not need OpenSSH Client.
$ControllerArch = Get-NativeArch
$sshKeygen = Join-Path (Join-Path $PayloadRoot $ControllerArch) "ssh-keygen.exe"
if (-not (Test-Path $sshKeygen)) {
    Fail ("Bundled ssh-keygen.exe is unavailable for controller architecture {0}." -f $ControllerArch)
}
Write-Step ("Using bundled ssh-keygen for controller architecture: {0}" -f $ControllerArch)

$UserSshDir = Join-Path $env:USERPROFILE ".ssh"
if (-not (Test-Path $UserSshDir)) {
    New-Item -ItemType Directory -Path $UserSshDir | Out-Null
}

$PrivateKey = Join-Path $UserSshDir $KeyName
$PublicKey = "$PrivateKey.pub"
$PublicComment = "ORION SUBSPACE BEACON Key"

if ($ForceNewKey -and (Test-Path $PrivateKey)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Move-Item $PrivateKey "$PrivateKey.backup-$stamp"
    if (Test-Path $PublicKey) {
        Move-Item $PublicKey "$PublicKey.backup-$stamp"
    }
}

if (-not (Test-Path $PrivateKey)) {
    Write-Step "Generating controller key: $PrivateKey"
    # Windows PowerShell 5.1 drops a truly empty native argument. Pass two
    # quote characters so the bundled ssh-keygen receives an empty passphrase.
    $EmptyPassphrase = [char]34 + [char]34
    & $sshKeygen -t ed25519 -f $PrivateKey -N $EmptyPassphrase -C $PublicComment | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Fail "Bundled ssh-keygen failed while generating the controller key."
    }
}
else {
    Write-Step "Reusing existing controller private key: $PrivateKey"
}

if (-not (Test-Path $PublicKey)) {
    Write-Step "Regenerating public key from existing private key."
    $derived = & $sshKeygen -y -f $PrivateKey
    if ($LASTEXITCODE -ne 0) {
        Fail "Bundled ssh-keygen failed while deriving the public key."
    }
    [System.IO.File]::WriteAllText($PublicKey, ($derived + "`r`n"), [System.Text.Encoding]::ASCII)
}

# Keep reruns aligned with the current product label without changing key material.
$publicFields = ([System.IO.File]::ReadAllText($PublicKey)).Trim() -split '\s+'
if ($publicFields.Count -ge 2) {
    $normalizedPublic = (($publicFields[0..1] -join " ") + " " + $PublicComment + "`r`n")
    [System.IO.File]::WriteAllText($PublicKey, $normalizedPublic, [System.Text.Encoding]::ASCII)
}

Copy-Item $PublicKey (Join-Path $IdentityDir "controller.pub") -Force
Write-Step "Copied public key to identity\controller.pub"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " ORION SUBSPACE BEACON Key prepared - ZERO PREREQUISITES" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Controller architecture:"
Write-Host ("  " + $ControllerArch) -ForegroundColor Yellow
Write-Host "Controller private key:"
Write-Host ("  " + $PrivateKey) -ForegroundColor Yellow
Write-Host ""
Write-Host "The private key stays on this controller PC."
Write-Host "The USB/package contains only the public key plus x86/x64/ARM64 SSH payloads."
Write-Host "No Windows OpenSSH Client installation was required."
