"""
System Resource Monitor - Runs in system tray
Notifies when CPU is throttling (including thermal throttling) or RAM usage >= 90%
"""

import psutil
import time
import threading
import io
from plyer import notification
from datetime import datetime
from PIL import Image, ImageDraw
import pystray
from pystray import MenuItem as item


# Configuration
RAM_THRESHOLD = 90  # percentage
TEMP_THRESHOLD = 85  # Celsius - alert above this
THERMAL_THROTTLE_TEMP = 90  # Celsius - thermal throttle likely above this
CPU_POLL_INTERVAL = 2  # seconds between checks
NOTIFICATION_COOLDOWN = 60  # seconds between repeated notifications


# Global state for tray updates
status_info = {
    "cpu_usage": 0.0,
    "ram_usage": 0.0,
    "cpu_temp": None,
    "warnings": [],
}

last_notifications = {
    "cpu": 0,
    "ram": 0,
    "temp": 0,
    "thermal": 0,
}

running = True


def create_icon_image():
    """Create a simple monitor icon"""
    # Create a 64x64 image with a shield/check icon
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Draw a simple shield shape
    draw.polygon(
        [(32, 4), (58, 16), (58, 36), (32, 58), (6, 36), (6, 16)],
        fill=(0, 180, 216, 255),
        outline=(0, 150, 180, 255),
    )
    # Draw a checkmark
    draw.line([(20, 32), (28, 40), (44, 24)], fill=(255, 255, 255, 255), width=3)

    return img


def get_cpu_usage():
    """Get current CPU usage percentage"""
    return psutil.cpu_percent(interval=1)


def get_ram_usage():
    """Get current RAM usage percentage"""
    return psutil.virtual_memory().percent


def send_notification(title, message):
    """Send Windows notification"""
    try:
        notification.notify(
            title=title,
            message=message,
            app_name="System Monitor",
            timeout=10,
        )
    except Exception as e:
        print(f"[{datetime.now()}] Notification error: {e}")


def get_cpu_temperature():
    """
    Get CPU temperature.
    Tries psutil first, falls back to WMI on Windows.
    Returns temperature in Celsius or None.
    """
    # Method 1: psutil sensors
    temps = psutil.sensors_temperatures()
    if temps:
        for key in ("cpu_thermal", "coretemp", "k10temp", "zenpower", "cpu"):
            if key in temps:
                return temps[key][0].current

    # Method 2: OpenHardwareMonitor WMI
    try:
        import wmi
        w = wmi.WMI(namespace=r"root\OpenHardwareMonitor")
        sensors = w.Sensor()
        cpu_temps = [
            float(s.Value)
            for s in sensors
            if s.SensorType == "Temperature"
            and "CPU" in s.Name
            and float(s.Value) > 0
        ]
        if cpu_temps:
            return max(cpu_temps)
    except Exception:
        pass

    # Method 3: ACPI thermal zones via WMI
    try:
        import wmi
        w = wmi.WMI(namespace="root\\wmi")
        thermal_zones = w.MSAcpi_ThermalZoneTemperature()
        if thermal_zones:
            temps_kelvin = [float(z.CurrentTemperature) / 10.0 for z in thermal_zones]
            if temps_kelvin:
                return max(temps_kelvin) - 273.15
    except Exception:
        pass

    return None


def check_cpu_throttling():
    """Check if CPU is throttling by detecting frequency reduction"""
    freq = psutil.cpu_freq()
    if freq is None:
        return False, 0

    usage_percent = get_cpu_usage()

    if freq.current < freq.max * 0.8 and usage_percent > 50:
        return True, usage_percent

    return False, usage_percent


def check_thermal_throttling():
    """Check if CPU is thermally throttling"""
    freq = psutil.cpu_freq()
    if freq is None:
        return False, None, 0

    temp = get_cpu_temperature()
    usage = get_cpu_usage()

    if temp is not None and temp >= THERMAL_THROTTLE_TEMP:
        if freq.current < freq.max * 0.85 and usage > 40:
            return True, temp, usage
        return True, temp, usage

    return False, temp, usage


def check_ram_threshold():
    """Check if RAM usage exceeds threshold"""
    ram_percent = get_ram_usage()
    return ram_percent >= RAM_THRESHOLD, ram_percent


def check_temperature():
    """Check if CPU temperature exceeds threshold"""
    temp = get_cpu_temperature()
    if temp is None:
        return False, None
    return temp >= TEMP_THRESHOLD, temp


def monitor_loop():
    """Background monitoring loop"""
    global running

    while running:
        try:
            current_time = time.time()

            # Get current stats
            cpu_usage = get_cpu_usage()
            ram_usage = get_ram_usage()
            cpu_temp = get_cpu_temperature()

            # Update status for tray
            status_info["cpu_usage"] = cpu_usage
            status_info["ram_usage"] = ram_usage
            status_info["cpu_temp"] = cpu_temp
            status_info["warnings"] = []

            # Check CPU throttling
            is_throttling, _ = check_cpu_throttling()
            if is_throttling and (current_time - last_notifications["cpu"] > NOTIFICATION_COOLDOWN):
                send_notification(
                    "⚠️ CPU Throttling Detected",
                    f"CPU is throttling! Usage: {cpu_usage:.1f}%\n"
                    f"Frequency reduced - check temperatures/power settings."
                )
                status_info["warnings"].append("CPU Throttling")
                last_notifications["cpu"] = current_time

            # Check thermal throttling
            is_thermal, temp, _ = check_thermal_throttling()
            if is_thermal and (current_time - last_notifications["thermal"] > NOTIFICATION_COOLDOWN):
                send_notification(
                    "🔥 Thermal Throttling Detected",
                    f"CPU is thermally throttling!\n"
                    f"Temperature: {temp:.1f}°C | Usage: {cpu_usage:.1f}%\n"
                    f"Check cooling - clean fans, improve airflow."
                )
                status_info["warnings"].append(f"Thermal: {temp:.0f}°C")
                last_notifications["thermal"] = current_time

            # Check RAM
            ram_exceeded, _ = check_ram_threshold()
            if ram_exceeded and (current_time - last_notifications["ram"] > NOTIFICATION_COOLDOWN):
                send_notification(
                    "🔴 High RAM Usage",
                    f"RAM usage is at {ram_usage:.1f}%!\n"
                    f"Consider closing some applications."
                )
                status_info["warnings"].append(f"RAM: {ram_usage:.0f}%")
                last_notifications["ram"] = current_time

            # Check temperature warning
            temp_high, temp_val = check_temperature()
            if temp_high and temp_val is not None and (current_time - last_notifications["temp"] > NOTIFICATION_COOLDOWN):
                send_notification(
                    "🌡️ High CPU Temperature",
                    f"CPU temperature is {temp_val:.1f}°C\n"
                    f"Approaching thermal throttle range."
                )
                status_info["warnings"].append(f"Temp: {temp_val:.0f}°C")
                last_notifications["temp"] = current_time

            time.sleep(CPU_POLL_INTERVAL)

        except Exception as e:
            print(f"[{datetime.now()}] Error: {e}")
            time.sleep(CPU_POLL_INTERVAL)


def update_tray_icon(icon):
    """Update the tray icon tooltip with current status"""
    while running:
        try:
            cpu = status_info["cpu_usage"]
            ram = status_info["ram_usage"]
            temp = status_info["cpu_temp"]
            warnings = status_info["warnings"]

            temp_str = f"{temp:.0f}°C" if temp else "N/A"
            warning_str = " | ".join(warnings) if warnings else "All OK"

            tooltip = (
                f"CPU: {cpu:.0f}% | RAM: {ram:.0f}% | Temp: {temp_str}\n"
                f"Status: {warning_str}"
            )

            icon.title = tooltip

        except Exception:
            pass

        time.sleep(2)


def on_quit(icon):
    """Handle quit action"""
    global running
    running = False
    icon.stop()


def on_status(icon):
    """Show current status in a notification"""
    cpu = status_info["cpu_usage"]
    ram = status_info["ram_usage"]
    temp = status_info["cpu_temp"]
    warnings = status_info["warnings"]

    temp_str = f"{temp:.0f}°C" if temp else "N/A"
    warning_str = "\n".join(warnings) if warnings else "No issues detected"

    send_notification(
        "📊 System Monitor Status",
        f"CPU Usage: {cpu:.1f}%\n"
        f"RAM Usage: {ram:.1f}%\n"
        f"CPU Temp: {temp_str}\n\n"
        f"Active Warnings:\n{warning_str}"
    )


def main():
    global running

    print("=" * 50)
    print("System Resource Monitor")
    print("=" * 50)
    print(f"RAM threshold: {RAM_THRESHOLD}%")
    print(f"CPU temp alert: {TEMP_THRESHOLD}°C")
    print(f"Thermal throttle alert: {THERMAL_THROTTLE_TEMP}°C")
    print(f"Check interval: {CPU_POLL_INTERVAL}s")
    print(f"Notification cooldown: {NOTIFICATION_COOLDOWN}s")
    print("-" * 50)
    print("Starting system tray monitor...\n")

    # Create tray icon
    icon_image = create_icon_image()

    menu = (
        item("View Status", on_status, default=True),
        item("Quit", on_quit),
    )

    icon = pystray.Icon(
        "System Monitor",
        icon_image,
        "System Monitor - Starting...",
        menu,
    )

    # Start monitoring thread
    monitor_thread = threading.Thread(target=monitor_loop, daemon=True)
    monitor_thread.start()

    # Start tray update thread
    tray_thread = threading.Thread(target=update_tray_icon, args=(icon,), daemon=True)
    tray_thread.start()

    # Run the tray icon (blocks until quit)
    icon.run()

    print("\nMonitor stopped.")


if __name__ == "__main__":
    main()
