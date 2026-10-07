# System Resource Monitor

Monitors your system and sends Windows notifications when:
- **CPU is throttling** (frequency reduced under load)
- **CPU is thermally throttling** (high temperature causing performance loss)
- **CPU temperature is high** (warning before thermal throttling)
- **RAM usage hits 90%** or above

Runs in the **system tray** (near the clock) with a status icon.

## Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Run the monitor:
```bash
start.bat
```

Or for a hidden background launch:
```bash
start-hidden.bat
```

## System Tray

The monitor runs in the system tray with an icon. You can:
- **Hover** over the icon to see live CPU, RAM, and temperature stats
- **Right-click** to view detailed status or quit

## Auto-Start with Windows

To have the monitor start automatically when Windows boots:

1. Double-click `install-autostart.bat`
2. The monitor will now launch hidden on startup

To remove auto-start, run `uninstall-autostart.bat`.

## Configuration

Edit these values in `monitor.py`:
- `RAM_THRESHOLD` - RAM percentage to trigger alert (default: 90%)
- `TEMP_THRESHOLD` - CPU temp warning level in °C (default: 85°C)
- `THERMAL_THROTTLE_TEMP` - Thermal throttle alert level in °C (default: 90°C)
- `CPU_POLL_INTERVAL` - Seconds between checks (default: 2s)
- `NOTIFICATION_COOLDOWN` - Seconds between repeated notifications (default: 60s)

## Notes

- Requires Python 3.7+
- Windows notifications require Windows 10/11
- Temperature monitoring may require [OpenHardwareMonitor](https://openhardwaremonitor.org/) for best results on Windows
- Right-click the tray icon to quit the monitor
