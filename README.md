# ORION SUBSPACE BEACON Key v1 — Offline Edition

Portable physical-presence Windows Subspace Beacon key for temporary LAN SSH administration of Windows machines you own or are authorized to manage.

## Behavior

- Payload deployment remains fully offline. The optional public-IP lookup runs only after deployment and never affects activation success.
- After activation, a non-failing network report shows RFC1918 private IPv4 addresses, other local/virtual addresses, and the public IPv4 when an external lookup is reachable.
- No GitHub, DNS, Internet, Tailscale, API token, or cloud service is required on the target.
- Run `ACTIVATE.cmd`, approve UAC, then discover/connect over the same LAN.
- Run `DEACTIVATE.cmd` to remove ORION-managed state.
- Existing system OpenSSH configuration is not modified.

## Included architectures

- x86 / 32-bit Windows → `payload\openssh\win32`
- x64 / AMD64 Windows → `payload\openssh\win64`
- ARM64 Windows → `payload\openssh\arm64`

Architecture selection is automatic, including WOW64 / Windows on ARM.

## USB

Filesystem: **FAT32**

Suggested volume label: `SUBSPACE BEACON`

## Prepare on Windows

1. Extract this package on the controller Windows PC.
2. Run `PREPARE-KEY.cmd`.
3. It verifies all three preloaded OpenSSH payloads.
4. It automatically selects the bundled x86/x64/ARM64 `ssh-keygen.exe` matching the controller Windows.
5. It creates or reuses `%USERPROFILE%\.ssh\orion_enrollment_ed25519`.
6. The private key remains on the controller.
7. Only `identity\controller.pub` is copied into SUBSPACE BEACON.
8. Copy the complete package to the FAT32 USB.

`PREPARE-KEY` performs no network download. **Windows OpenSSH Client is not required**; SUBSPACE BEACON uses its own bundled `ssh-keygen.exe`.

## Source distribution

The source repository intentionally does not contain a generated
identity\controller.pub. Run PREPARE-KEY.cmd on the controller before
deployment. Generated public enrollment keys are ignored by Git because they
belong to one deployment and must not be reused as a repository default.

## Target activation

1. Insert SUBSPACE BEACON into an authorized target.
2. Run `ACTIVATE.cmd`.
3. Approve UAC.
4. SUBSPACE BEACON selects the matching offline payload.
5. It creates the isolated ORION Subspace Beacon endpoint on TCP 22022 for the local subnet and RFC1918 private LAN ranges.
6. On the controller, run `SCAN-LAN.cmd`. Automatic discovery reads physical/private LAN routes and ignores proxy/VPN-only routes.

## Removal

Run `DEACTIVATE.cmd` on the target.

## Source archive SHA-256

- OpenSSH-Win32.zip: `de65a5cc1c43192bbc7e5fc527ba435c9d1668713f062eaf1298932e28995085`
- OpenSSH-Win64.zip: `0ca131f3a78f404dc819a6336606caec0db1663a692ccc3af1e90232706ada54`
- OpenSSH-ARM64.zip: `9c1c2e346ea7c76ddbd7e82e231c014e9e30fd497550c727adcdfdb8ca08642d`

## Windows integration tests still required

- Windows 7 x86 if available
- Windows 7 x64 / ThinkPad L330
- Windows 10/11 x64
- Windows 11 ARM64 if available
- Internet physically disconnected during ACTIVATE
- repeated ACTIVATE / DEACTIVATE
- reboot persistence
- existing system OpenSSH
- TCP 22022 already occupied
