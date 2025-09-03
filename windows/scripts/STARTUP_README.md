# WiFi Speedtest Script - Startup Setup

This document explains how to set up the WiFi speedtest script to run automatically on Windows startup.

## Quick Setup

Run `setup_startup.bat` as Administrator and choose your preferred method.

## Startup Methods

### 1. Task Scheduler (Recommended)
- **Pros**: Runs with admin privileges, more reliable, runs at boot (not just login)
- **Cons**: Requires admin rights to set up
- **Best for**: Systems where you want the script to run regardless of user login

### 2. Startup Folder
- **Pros**: Simple setup, no admin rights needed
- **Cons**: Only runs when user logs in, may not have admin privileges
- **Best for**: Personal computers where you always log in

### 3. Registry Run Key
- **Pros**: Runs at login, persistent across reboots
- **Cons**: May not have admin privileges, harder to remove
- **Best for**: When you need registry-based startup

## Manual Setup Instructions

### Task Scheduler (Manual)
1. Open Task Scheduler (`taskschd.msc`)
2. Click "Create Task..."
3. General tab:
   - Name: "WiFi Speedtest Script"
   - Check "Run with highest privileges"
4. Triggers tab:
   - Click "New..."
   - Begin the task: "At startup"
5. Actions tab:
   - Click "New..."
   - Action: "Start a program"
   - Program/script: `C:\path\to\your\install.bat`
   - Start in: `C:\path\to\your\scripts\folder`

### Startup Folder (Manual)
1. Press `Win + R`, type `shell:startup`, press Enter
2. Create a shortcut to `install.bat` in this folder
3. Right-click the shortcut → Properties → Advanced → "Run as administrator" (if needed)

### Registry (Manual)
1. Press `Win + R`, type `regedit`, press Enter
2. Navigate to: `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`
3. Right-click → New → String Value
4. Name: "WiFi Speedtest Script"
5. Value: `"C:\path\to\your\install.bat"`

## Troubleshooting

### Script doesn't start
- Check if the script path is correct
- Ensure `speedtest.exe` is in the same folder
- Run the script manually first to test

### Permission issues
- Use Task Scheduler method for admin privileges
- Or run `setup_startup.bat` as Administrator

### Script stops running
- Check Windows Event Viewer for errors
- Ensure the script has proper error handling
- Verify network connectivity

## Removing Startup

### Task Scheduler
- Open Task Scheduler → Find "WiFi Speedtest Script" → Delete

### Startup Folder
- Delete the shortcut from the Startup folder

### Registry
- Run: `reg delete "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run" /v "WiFi Speedtest Script" /f`
