@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0local_test_renderer.ps1"
if errorlevel 1 pause
