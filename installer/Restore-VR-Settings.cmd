@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Configure-VR.ps1" -Action Restore
pause
