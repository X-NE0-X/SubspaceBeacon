# Subspace Beacon: Operations and Troubleshooting

This reference is for an agent operating the portable Windows Beacon in an authorized environment. It records the deployment contract and the failures found during real mixed-version Windows testing.

## 1. Identify the role and the actual path

The controller is the machine that owns the private enrollment key. The target is the machine that runs SUBSPACERELAY.

Controller defaults:

```text
private key: %USERPROFILE%\.ssh\orion_enrollment_ed25519
public key exported to USB: identity\controller.pub
target user: ORION-RELAY
target port: 22022
target state: C:\ProgramData\ORION
```

The controller package normally needs Python 3 and a working system ssh.exe. SCAN-LAN.cmd prefers py -3 and falls back to python. It does not need a resident controller daemon.

The target package selects the bundled x86, x64, or ARM64 payload according to the target architecture. Preserve that selection logic. A 32-bit Windows target needs the win32 payload even when the controller is x64.

Use the script directory as the working directory. Do not depend on a USB drive letter because it can change. The scripts should resolve their own directory.

## 2. One-time key preparation

Run PREPARE-KEY.cmd on the controller. The intended behavior is:

1. Verify every bundled payload.
2. Select the bundled ssh-keygen matching the controller architecture.
3. Create or reuse %USERPROFILE%\.ssh\orion_enrollment_ed25519.
4. Copy only the .pub file to identity\controller.pub.

The private key never belongs on the USB drive. If key generation prints the full ssh-keygen usage text with Too many arguments, inspect quoting and argument order. A safe shape is:

```text
ssh-keygen -t ed25519 -f "C:\exact\path\orion_enrollment_ed25519" -N "" -C "ORION controller"
```

Use the bundled executable that matches the controller architecture. Do not silently fall back to a random system binary when the offline package promises a bundled payload.

## 3. Target activation and rollback

ACTIVATE.cmd must be run elevated. A successful activation should create the local service account, copy the isolated OpenSSH payload, generate host keys, create the service, create a local-subnet firewall rule, and start the service. The endpoint marker and endpoint.json must be created under C:\ProgramData\ORION.

Check the target locally with commands available on that Windows version:

```text
sc query SUBSPACERELAY
sc qc SUBSPACERELAY
netstat -ano | findstr :22022
type C:\ProgramData\ORION\endpoint.json
```

On newer PowerShell, these are useful supplements:

```powershell
Get-Service -Name SUBSPACERELAY
Get-NetFirewallRule -DisplayName '*ORION*'
Get-NetTCPConnection -LocalPort 22022
```

If any owned step fails, rollback must remove only changes made by this activation attempt. A previous ORION-RELAY account or C:\ProgramData\ORION directory requires inspection first. DEACTIVATE.cmd and the marker C:\ProgramData\ORION\.orion-subspace-beacon-v1 define the cleanup boundary. Never recursively delete an unmarked directory merely because its name resembles ORION state.

After a failure, inspect the first substantive red error. Subspace Beacon FAILED. Exit code: 99 is a wrapper result, not a diagnosis.

## 4. LAN discovery

The scanner uses TCP reachability plus authenticated endpoint verification. It defaults to TCP 22022, user ORION-RELAY, and the controller private key. It discovers physical private LAN routes from route print -4 on Windows and filters out VPN, Wintun, WSL, proxy-only, and other non-LAN routes where possible.

Normal commands:

```text
SCAN-LAN.cmd
py -3 controller\discover.py
py -3 controller\discover.py --connect
py -3 controller\discover.py --subnet 192.168.31.0/24 --connect
```

--connect requires exactly one authenticated endpoint. Multiple verified endpoints are an ambiguity and should be resolved by an explicit subnet or known address. A subnet override is appropriate only after the route and gateway have been verified.

Known-target verification:

```powershell
Test-NetConnection -ComputerName 192.168.31.143 -Port 22022
```

Then use the actual controller key:

```text
ssh.exe -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=8 -i "C:\Users\<controller>\.ssh\orion_enrollment_ed25519" -p 22022 ORION-RELAY@192.168.31.143
```

Ping is useful evidence only when it succeeds. A failed ICMP ping does not prove that TCP 22022 is unreachable. A successful TCP test does not prove that SSH authentication is valid. Both network reachability and key authentication matter.

## 5. 5 GHz and 2.4 GHz with one SSID

Band steering does not itself break Beacon. The important properties are the resulting address, mask, gateway, VLAN, and client isolation policy.

On each machine collect:

```text
ipconfig /all
route print -4
netsh wlan show interfaces
netsh wlan show drivers
```

Compare:

```text
controller IPv4     target IPv4
controller mask     target mask
controller gateway  target gateway
controller route    target route
```

Examples:

- 192.168.31.143/24 and 192.168.31.50/24 with gateway 192.168.31.1 are normally the same private LAN.
- 192.168.31.x and 192.168.50.x may be separate VLANs even when the SSID text is identical.
- 169.254.x.x indicates that the old machine did not obtain a DHCP lease.
- A 5 GHz-capable router does not imply that an old adapter supports the band, its channel width, or its WPA mode.

If the router exposes one combined SSID and the old adapter cannot select a band, inspect netsh wlan show interfaces and the router association list. Temporarily using a known-compatible 2.4 GHz connection is a diagnostic step. Avoid static IP configuration until DHCP, gateway, and VLAN behavior are understood.

Guest networking, AP/client isolation, mesh policies, and firewall profiles can block peer traffic even with matching-looking addresses. A Beacon failure in that case is a network-policy problem, not an SSH key problem.

## 6. Windows firewall and local-subnet policy

Activation should create a narrowly scoped local-subnet firewall rule. If creation fails, do not silently expose the service on all profiles or all addresses. Inspect:

```text
netsh advfirewall show allprofiles
netsh advfirewall firewall show rule name=all
```

Verify the detected local subnet and active network profile. A rule failure can result from an invalid subnet string, an old firewall API, policy management, or insufficient rights. Preserve rollback and report the exact policy failure.

## 7. Clash/Mihomo and proxy paths

Beacon discovery is a direct private-LAN operation. An HTTP proxy or a normal system proxy setting cannot make a disconnected LAN reachable. A Clash/Mihomo TUN can still alter routes even when the Windows proxy toggle is off.

Inspect the active state, not just a profile file:

```text
tasklist /v
route print -4
ipconfig /all
```

On newer PowerShell:

```powershell
Get-NetIPConfiguration
Get-NetRoute -AddressFamily IPv4
Get-NetAdapter
```

When a TUN route captures private traffic, test the exact target address with Test-NetConnection and inspect the route chosen for that address. Temporarily disabling TUN or the system proxy can isolate the cause when the user has authorized that change. Restore the intended proxy state after the test.

Clash routing and DNS fake-IP behavior are separate layers. A rule such as DOMAIN-SUFFIX,ts.net,DIRECT affects routing for matching names. dns.fake-ip-filter affects address synthesis. Fixing one does not automatically fix the other. Direct numeric LAN addresses avoid DNS ambiguity during Beacon diagnosis.

If an interactive Clash Verge app shows an empty or new profile after a configuration copy, inspect the Windows account that owns the GUI process. User configuration is under:

```text
C:\Users\<interactive-user>\AppData\Roaming\io.github.clash-verge-rev.clash-verge-rev
```

Copying only to the service account profile does not populate the interactive desktop app. Confirm ownership with tasklist /v or query user. Before reopening the app, validate a copied Mihomo profile with its bundled binary using the profile's -t configuration test. Do not copy logs, caches, or active lock files as configuration.

## 8. Tailscale

Tailscale is optional for same-LAN Beacon use. The scanner is designed to find physical private LAN endpoints, not to infer a Tailscale path. Tailscale addresses in 100.64.0.0/10 can be valid for direct SSH when routes and ACLs allow them, yet they are intentionally outside the normal physical-LAN scan.

If Tailscale is involved:

1. Confirm the service is running and identify the interactive account that owns the login.
2. Use the direct target address and Test-NetConnection or ssh -G.
3. Inspect route print -4 and TUN routes.
4. Do not force --subnet 100.x unless the target actually listens there and the route is known to work.

Running tailscale status as a service account can produce 401 or Tailscale already in use by <interactive user>. That means the CLI context is wrong. It does not prove that the interactive Tailscale session is logged out. Run the check in the owning interactive account.

For a Tailscale hostname, verify both the direct route and DNS policy. ts.net direct routing and fake-IP exclusion are independent settings.

## 9. Windows 7 and old PowerShell compatibility

Windows 7 frequently runs Windows PowerShell 2.0. It lacks newer networking cmdlets and has stricter or different behavior around parameter binding, ACLs, services, and cryptographic types. Use capability-based fallbacks so the same package remains usable on Windows 10 and Windows 11.

Compatibility rules:

- Use ipconfig, route print, netsh, sc, and netstat as the baseline diagnostics.
- Validate every path and service name before passing it to a cmdlet. An empty $Path, $hostKeyFile, or $ServiceName causes misleading parameter-binding errors.
- Quote paths containing spaces and prefer explicit variables with a nonempty-value check.
- Avoid relying on modern PowerShell syntax or cmdlets in the Win7 path.
- Do not pass a crypto provider through an incompatible IDisposable conversion. Use the concrete provider API and explicit cleanup supported by that PowerShell version.
- Treat Write-Manifest or similar parser errors as a script-generation or argument-binding bug. Do not cure them by repeatedly rerunning as administrator.
- Keep the modern path intact. Win7 fallbacks should be selected by capability or OS version, not hard-coded for every Windows release.

Historical examples:

```text
System.Management.Automation.ParameterBindingException
System.Security.Cryptography.RNGCryptoServiceProvider cannot be converted to IDisposable
Write-Manifest <<< $UserCreated
Test-Path received an empty Path
Start-Service received an empty or malformed service name
```

Each points to a script compatibility or value-validation defect. The agent should fix the smallest affected branch and retest on the target version.

## 10. OpenSSH payload and host-key ACL failures

The most important service-start failure on old Windows was OpenSSH rejecting host keys because inherited ACLs were too open:

```text
WARNING: UNPROTECTED PRIVATE KEY FILE!
Bad permissions
sshd: no hostkeys available -- exiting.
```

Another observed failure was OpenSSH rejected the generated configuration. In both cases, read the isolated sshd.log under the ORION state directory and validate the generated files before retrying the service.

The private host-key files must be readable by the service's effective identity and inaccessible to unrelated users. Use the package's ACL helper when available. If manual repair is necessary, operate on the exact files under C:\ProgramData\ORION\hostkeys, remove inherited grants, and grant only the identities required by the service. Never grant Everyone or broad interactive-user access to private host keys.

For example, after confirming the service identity and exact file:

```text
icacls "C:\ProgramData\ORION\hostkeys\ssh_host_ed25519_key" /inheritance:r
icacls "C:\ProgramData\ORION\hostkeys\ssh_host_ed25519_key" /grant:r "SYSTEM:F" "Administrators:F"
```

The exact ACL may vary with the service configuration. Verify the resulting ACL and sshd.log; do not assume that administrator elevation automatically makes the current account the owner. An elevated administrator can still lack ownership or a required access-control entry.

Observed related failures:

- Failed to set SYSTEM as owner of C:\ProgramData\ORION: ownership or ACL policy blocked the repair. Verify the exact ORION path and use icacls or takeown only within that path.
- Failed to harden private key ... LiteralPath: the key path variable was empty or the old PowerShell binder did not receive the expected parameter.
- Unable to load host key followed by no hostkeys available: generation, copy, ACL, or configuration validation failed earlier.
- Service remains in start-pending and then fails: inspect sshd.log before changing the service definition.

## 11. Stale files, locked payloads, and reruns

ORION-RELAY already exists can mean a previous attempt left an account or service. Check:

```text
sc query SUBSPACERELAY
sc qc SUBSPACERELAY
net user ORION-RELAY
dir C:\ProgramData\ORION
```

If the marker identifies ORION-owned state, use the supported deactivation or rollback path. If the directory is unmarked, stop and preserve it for inspection.

An error such as:

```text
The process cannot access the file ... OpenSSH\libcrypto.dll because it is being used by another process
```

means a prior relay or OpenSSH process still holds the isolated payload. Stop the exact ORION service and process, then retry the copy. Stage a new payload instead of overwriting a loaded DLL. Reboot only when the exact lock cannot be released and the user has approved the interruption.

Do not solve stale state by formatting the USB. Verify the volume label and root contents first. A finalized Beacon USB should contain the component directories and scripts, with no Windows installation boot, efi, sources, support, setup.exe, or ISO files.

## 12. Remote connection symptoms

Not allowed at this time, a transient timeout, or a refused connection can occur while the service is restarting, while stale sessions exist, or while a TUN/firewall route is changing. Wait briefly and perform one bounded retry. Then check service state, TCP reachability, and the relay log. Do not spam retries or rewrite configuration without evidence.

If the account authenticates but an interactive command is unavailable, remember that ORION-RELAY is a service account. Desktop applications, Clash profiles, and Tailscale login state belong to the interactive desktop account and must be inspected there.

## 13. Validation checklist

Controller:

```text
where py
py -3 --version
where ssh
if exist "%USERPROFILE%\.ssh\orion_enrollment_ed25519" echo key-present
route print -4
```

Target:

```text
sc query SUBSPACERELAY
sc qc SUBSPACERELAY
netstat -ano | findstr :22022
if exist C:\ProgramData\ORION\endpoint.json type C:\ProgramData\ORION\endpoint.json
```

End to end:

```powershell
Test-NetConnection -ComputerName <target-ip> -Port 22022
```

Then complete an authenticated SSH or discover.py --connect result. Do not print or paste private keys, generated passwords, proxy subscription URLs, or other secrets into logs or reports.

## 14. Public and private IP output

The Beacon output may show the target's private address and an optional public-IP lookup. The public lookup is informational and should be non-failing. LAN discovery and SSH require the private address and route. A public IP does not prove that the target is reachable from the controller and does not create a port-forwarding path.
