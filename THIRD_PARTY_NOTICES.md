# Third-party notices

The project code and integration scripts in this repository are released under
the MIT License in LICENSE.

The offline payload directories contain Win32-OpenSSH 9.8p2 artifacts for
win32, win64, and arm64. Each payload keeps its upstream LICENSE.txt and
NOTICE.txt files. Those files remain applicable to the bundled third-party
payload and are included in every architecture directory.

Upstream references:

- https://github.com/PowerShell/Win32-OpenSSH
- https://github.com/PowerShell/Win32-OpenSSH/releases
- https://learn.microsoft.com/windows-server/administration/openssh/openssh-overview

The generated controller public key is deployment-specific and is intentionally
excluded from the source repository. Run PREPARE-KEY.cmd before using a source
checkout as a deployment package.
