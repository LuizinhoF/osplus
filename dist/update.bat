@echo off
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" %*
if errorlevel 1 (
    echo.
    echo [ERROR] OSPlus update failed.
    pause
    exit /b 1
)

exit /b 0
