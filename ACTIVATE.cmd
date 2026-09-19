@echo off
setlocal
cd /d "%~dp0"
echo ORION compatibility build 20260918-NETSH-PROCESS-BOOL-OWNER-RESTORE-ROLLBACK-ACLORDER-PAYLOAD-HOSTKEY-EXACTACL-PS2ACL-NOREADBACK-OWNERCAST-VALIDATE-FIRST-ROUTE-AUTO-PRIVATE-LAN-IP-REPORT-SERVICE-STOP-BEFORE-REFRESH-SSHD-VALIDATE-DETAIL-EMPTY-HOSTKEY-PASSPHRASE-RECOVERY-LATE-MARKER-KEYGEN-PROCESS-ARGS

fltmc >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Requesting administrator privileges...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%ComSpec%' -ArgumentList '/c ""%~f0""' -Verb RunAs"
  exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\activate.ps1"
set RC=%errorlevel%
echo.
if "%RC%"=="0" (
  echo ORION Subspace Beacon deployed.
) else (
  echo ORION Subspace Beacon FAILED. Exit code: %RC%
)
echo.
pause
exit /b %RC%
