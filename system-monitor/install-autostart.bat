@echo off
echo Installing System Resource Monitor for auto-start...
echo.

cd /d "%~dp0"

REM Get the full path to start-hidden.bat
set FULL_PATH=%~dp0start-hidden.bat

REM Create a shortcut in the startup folder
set STARTUP_FOLDER=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup

echo Creating shortcut in startup folder...
powershell -Command "$WshShell = New-Object -ComObject WScript.Shell; $Shortcut = $WshShell.CreateShortcut('%STARTUP_FOLDER%\SystemMonitor.lnk'); $Shortcut.TargetPath = '%FULL_PATH%'; $Shortcut.WorkingDirectory = '%~dp0'; $Shortcut.WindowStyle = 0; $Shortcut.Save()"

echo.
echo Done! The monitor will now start automatically with Windows.
echo It will run in the background and show in the system tray.
echo.
pause
