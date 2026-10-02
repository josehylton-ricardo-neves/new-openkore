@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watcherctl.ps1" %*
exit /b %ERRORLEVEL%
