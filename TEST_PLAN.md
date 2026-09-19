# ORION Subspace Beacon Key v1 integration test plan

## Matrix

1. Windows 7 SP1 x64 — primary L330 target
2. Windows 10 x64
3. Windows 11 x64
4. Optional Windows 7 x86 VM

## Preparation

- Run PREPARE-KEY.cmd on the Windows controller.
- Confirm `identity/controller.pub` is a real public key.
- Confirm all three payload directories contain `sshd.exe`, `ssh-keygen.exe`, `sftp-server.exe`, DLLs, and support files.

## Test A — clean activation

- Ensure no `ORION-RELAY` user.
- Ensure no `SUBSPACERELAY` service.
- Ensure TCP/22022 is unused.
- Run ACTIVATE.cmd and approve UAC.
- Expect exit code 0.
- Verify service `SUBSPACERELAY` is Running and Automatic.
- Verify firewall rules `ORION-SSH-22022` and `ORION-SSH-22022-PRIVATE-LAN` are inbound allow, TCP/22022, LocalSubnet plus RFC1918 private ranges.
- Verify `C:\ProgramData\ORION\endpoint.json` parses as JSON.
- Verify password SSH login fails.
- Verify controller-key SSH login succeeds.
- Verify remote command `whoami` returns the `ORION-RELAY` account.
- Verify remote command can perform an administrator-only operation or inspect token groups.

## Test B — LAN discovery

- Run `python3 controller/discover.py` with active physical/private LAN routes and proxy/VPN adapters present.
- Endpoint must be listed only after SSH verification.
- Run with `--connect` and verify interactive shell.

## Test C — idempotence

- Record endpoint device_id.
- Run ACTIVATE.cmd again.
- Expect success.
- Verify same device_id.
- Verify only one service and one firewall rule exist.
- Verify SSH still works.

## Test D — safe collisions

- Run DEACTIVATE.cmd.
- Manually create local user `ORION-RELAY`; ACTIVATE must abort without altering it.
- Remove user.
- Bind another process to TCP/22022; ACTIVATE must abort without replacing it.

## Test E — rollback

- Clean activation.
- Run DEACTIVATE.cmd.
- Verify service removed.
- Verify firewall rule removed.
- Verify ORION-created account removed.
- Verify `C:\ProgramData\ORION` removed.
- Verify any unrelated system OpenSSH service/configuration remains untouched.

## Test F — reboot

- Activate cleanly.
- Reboot target.
- Verify SUBSPACERELAY starts automatically.
- Verify LAN discovery and SSH work without local login.

## Win7-specific checks

- Confirm bundled `sshd.exe` launches without missing API/CRT dependency errors.
- Confirm PowerShell script parses under the installed Win7 PowerShell version.
- Confirm `netsh advfirewall ... remoteip=LocalSubnet` and the RFC1918 private-LAN rule succeed.
- Confirm ADSI user creation and SID-based Administrators lookup succeed on localized Windows.
- If PowerShell 2.0 parsing fails anywhere, preserve compatibility by changing only the incompatible construct rather than raising the minimum version unless unavoidable.

## Offline payload tests

- [ ] ACTIVATE succeeds with Internet physically disconnected.
- [ ] x86 selects payload\openssh\win32.
- [ ] x64 selects payload\openssh\win64.
- [ ] ARM64 selects payload\openssh\arm64.
- [ ] PREPARE-KEY performs no network request.
- [ ] DEACTIVATE succeeds after each architecture test.

## Controller zero-prerequisite test

- [ ] Remove/disable system OpenSSH Client on the controller.
- [ ] PREPARE-KEY still generates/reuses the controller key successfully.
- [ ] Bundled `ssh-keygen.exe` is used for the native architecture.
