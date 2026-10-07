@echo off
setlocal
title RDP Shortcut Forge
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0RDPShortcutForge.ps1"
if errorlevel 1 (
    echo.
    echo RDP Shortcut Forge stopped because of an error.
    echo Review the message above, then press any key to close.
    pause >nul
)
endlocal
