@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0client-download-status.ps1" -Watch
pause
