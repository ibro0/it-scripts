@echo off
cd /d "%~dp0"
echo Starting System Resource Monitor...
echo The monitor will appear in the system tray (near the clock).
echo Right-click the icon to view status or quit.
echo.
python monitor.py
