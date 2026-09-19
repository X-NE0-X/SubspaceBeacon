@echo off
setlocal
cd /d "%~dp0"

echo.
echo ==========================================
echo    ORION SUBSPACE BEACON KEY - WINDOWS PREP
echo ==========================================
echo.
echo OFFLINE MODE: no payload download is performed.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PREPARE-KEY.ps1"
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" (
    echo Preparation failed with exit code %RC%.
    pause
    exit /b %RC%
)

echo Preparation complete.
pause
exit /b 0
