@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "(New-Object Media.SoundPlayer 'C:\Windows\Media\ring01.wav').PlaySync()"