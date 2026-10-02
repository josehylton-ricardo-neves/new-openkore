@echo off
setlocal

REM ============================================================
REM ONLINE WATCHER
REM ============================================================

if /I "%~1"=="watcher" (
    if "%~2"=="" (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0online-guard\watcherctl.ps1" status
    ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0online-guard\watcherctl.ps1" "%~2"
    )

    exit /b %ERRORLEVEL%
)

REM ============================================================
REM OPENKORE NORMAL
REM ============================================================

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0okmode.ps1" %*

exit /b %ERRORLEVEL%