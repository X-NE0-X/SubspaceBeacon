@echo off
setlocal
cd /d "%~dp0"
echo ORION LAN discovery and SSH handoff

where py >nul 2>&1
if not errorlevel 1 goto use_py_launcher

where python >nul 2>&1
if not errorlevel 1 goto use_python
echo Python 3 was not found on the controller.
set RC=2
goto report

:use_py_launcher
py -3 "%~dp0controller\discover.py" --connect
goto capture

:use_python
python "%~dp0controller\discover.py" --connect

:capture
set RC=%errorlevel%

:report
echo.
if "%RC%"=="0" goto success
echo ORION LAN discovery failed with exit code %RC%.
pause
:success
exit /b %RC%
