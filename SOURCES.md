# Upstream references

- Win32-OpenSSH install wiki: https://github.com/PowerShell/Win32-OpenSSH/wiki/Install-Win32-OpenSSH
  - Documents GitHub test releases as installable on Windows 7 and later.
  - Documents `netsh advfirewall` as the compatibility path on older Windows clients.
- Win32-OpenSSH Windows-specific sshd_config notes: https://github.com/PowerShell/Win32-OpenSSH/wiki/sshd_config
  - Documents `-f` custom configuration path.
  - Documents Windows `AllowUsers` behavior and absolute `AuthorizedKeysFile` handling.
  - Lists Windows-unsupported sshd_config directives that this package intentionally avoids.
- Win32-OpenSSH various considerations: https://github.com/PowerShell/Win32-OpenSSH/wiki/Various-Considerations
  - Documents registering Win32 OpenSSH sshd under a different Windows service name.
- Microsoft OpenSSH overview: https://learn.microsoft.com/windows-server/administration/openssh/openssh-overview
  - Documents built-in OpenSSH availability beginning with Windows 10 build 1809 / Server 2019.
- Win32-OpenSSH release page: https://github.com/PowerShell/Win32-OpenSSH/releases
- Payload pinned by this package: `OpenSSH_9.8p2 for Windows` (file version `9.8.3.0`).
