# Agent handoff: ORION Subspace Beacon Key v1

Goal: integration-test and minimally repair this package on real Windows, beginning with the ThinkPad L330 / Windows 7 SP1 x64 if available.

## Intended contract

1. Physical user inserts USB and double-clicks `ACTIVATE.cmd`.
2. One UAC approval is allowed.
3. Target becomes reachable only on the local subnet via SSH TCP/22022.
4. Authentication is public-key only. USB contains only the public key.
5. Target-side account is `ORION-RELAY`, local Administrators member, random password never exported.
6. Existing system OpenSSH must remain untouched.
7. `DEACTIVATE.cmd` must remove only ORION-owned state.
8. Re-running ACTIVATE must be idempotent.
9. No Tailscale, public relay, API key, credential harvesting, autorun, or stealth behavior belongs in v1.

## Before target testing

Run `PREPARE-KEY.cmd` on the Windows controller so the OpenSSH payloads and controller public key exist. The direct PowerShell entry point is:

`powershell -ExecutionPolicy Bypass -File .\PREPARE-KEY.ps1`

Then run local static checks:

```bash
python3 -m py_compile controller/discover.py tests/test_discover.py
pytest -q tests/test_discover.py
bash -n controller/discover.command
```

## Highest-risk integration assumptions to verify first

1. PowerShell syntax compatibility on the actual Win7 PowerShell version.
2. Win32-OpenSSH 9.8p2 / file version 9.8.3.0 actually launches on that Win7 image without missing CRT/API dependencies.
3. `SUBSPACERELAY` starts correctly under a non-default service name. Microsoft/PowerShell's own Win32-OpenSSH wiki documents alternate service names as supported.
4. `sc.exe privs` succeeds and SSH can create an interactive session.
5. The explicit absolute `AuthorizedKeysFile` works for the local Administrators-group account.
6. SSH session has the intended administrative token. Test `whoami /groups` plus an administrator-only operation. Do not change global UAC/LocalAccountTokenFilterPolicy unless the test proves it is needed; if a registry change becomes necessary, make it reversible and preserve the previous value in the manifest.
7. Win7 `netsh advfirewall ... remoteip=LocalSubnet` works exactly as expected.
8. `ssh-keygen -N '""'` stays non-interactive under Windows PowerShell.

## Repair discipline

Make the smallest change that fixes a demonstrated failure. Preserve the product contract above. Do not replace the isolated service with the system `sshd` service unless the custom-service approach is conclusively impossible on the tested build.

After every target-side change, rerun clean activation, SSH login, reboot persistence, idempotent activation, and full deactivation.

See `TEST_PLAN.md` for the full matrix.

## OFFLINE + ARM64 acceptance

- Target Internet must be disconnected during ACTIVATE.
- No runtime download is permitted.
- Verify x86 -> win32, AMD64 -> win64, ARM64 -> arm64.
- Verify ARM64 under WOW64 does not fall through to win64.

## Zero-prerequisite controller preparation

- Test PREPARE-KEY on a Windows controller with system `ssh-keygen.exe` / OpenSSH Client absent.
- PREPARE-KEY must select `payload\openssh\<native-arch>\ssh-keygen.exe`.
- Verify x86, x64 and ARM64 controller architecture selection where environments are available.
