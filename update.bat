@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-extensions.ps1" -OpenChrome
echo.
pause
