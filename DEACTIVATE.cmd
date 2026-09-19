@echo off
setlocal
cd /d "%~dp0"

fltmc >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Requesting administrator privileges...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%ComSpec%' -ArgumentList '/c ""%~f0""' -Verb RunAs"
  exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\deactivate.ps1"
set RC=%errorlevel%
echo.
if "%RC%"=="0" (
  echo ORION Subspace Beacon deactivation completed.
) else (
  echo ORION Subspace Beacon deactivation FAILED. Exit code: %RC%
)
echo.
pause
exit /b %RC%
