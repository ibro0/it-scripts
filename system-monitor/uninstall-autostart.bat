@echo off
echo Removing System Resource Monitor from auto-start...
echo.

set STARTUP_FOLDER=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup

if exist "%STARTUP_FOLDER%\SystemMonitor.lnk" (
    del "%STARTUP_FOLDER%\SystemMonitor.lnk"
    echo Removed from startup.
) else (
    echo No startup shortcut found.
)

echo.
pause
