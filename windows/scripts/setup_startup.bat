@echo off
echo Setting up WiFi Speedtest Script for Windows Startup
echo ===================================================
echo.

REM Get the current directory where this script is located
set "SCRIPT_DIR=%~dp0"
set "BATCH_FILE=%SCRIPT_DIR%install.bat"

echo Current script directory: %SCRIPT_DIR%
echo Batch file to run: %BATCH_FILE%
echo.

echo Choose startup method:
echo 1. Task Scheduler (Recommended - runs with admin privileges)
echo 2. Startup Folder (Simple - runs when user logs in)
echo 3. Registry Run Key (Alternative method)
echo 4. Exit
echo.

set /p choice="Enter your choice (1-4): "

if "%choice%"=="1" goto task_scheduler
if "%choice%"=="2" goto startup_folder
if "%choice%"=="3" goto registry_run
if "%choice%"=="4" goto exit
goto invalid_choice

:task_scheduler
echo.
echo Setting up Task Scheduler...
echo This will create a task that runs the script at startup with admin privileges.
echo.

REM Create XML file for task scheduler
echo ^<?xml version="1.0" encoding="UTF-16"?^> > "%TEMP%\wifi_speedtest_task.xml"
echo ^<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task"^> >> "%TEMP%\wifi_speedtest_task.xml"
echo   ^<RegistrationInfo^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<Description^>WiFi Speedtest and Reconnection Script^</Description^> >> "%TEMP%\wifi_speedtest_task.xml"
echo   ^</RegistrationInfo^> >> "%TEMP%\wifi_speedtest_task.xml"
echo   ^<Triggers^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<BootTrigger^> >> "%TEMP%\wifi_speedtest_task.xml"
echo       ^<Enabled^>true^</Enabled^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^</BootTrigger^> >> "%TEMP%\wifi_speedtest_task.xml"
echo   ^</Triggers^> >> "%TEMP%\wifi_speedtest_task.xml"
echo   ^<Principals^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<Principal id="Author"^> >> "%TEMP%\wifi_speedtest_task.xml"
echo       ^<LogonType^>InteractiveToken^</LogonType^> >> "%TEMP%\wifi_speedtest_task.xml"
echo       ^<RunLevel^>HighestAvailable^</RunLevel^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^</Principal^> >> "%TEMP%\wifi_speedtest_task.xml"
echo   ^</Principals^> >> "%TEMP%\wifi_speedtest_task.xml"
echo   ^<Settings^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<MultipleInstancesPolicy^>IgnoreNew^</MultipleInstancesPolicy^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<DisallowStartIfOnBatteries^>false^</DisallowStartIfOnBatteries^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<StopIfGoingOnBatteries^>false^</StopIfGoingOnBatteries^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<AllowHardTerminate^>true^</AllowHardTerminate^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<StartWhenAvailable^>true^</StartWhenAvailable^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<RunOnlyIfNetworkAvailable^>false^</RunOnlyIfNetworkAvailable^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<IdleSettings^> >> "%TEMP%\wifi_speedtest_task.xml"
echo       ^<StopOnIdleEnd^>false^</StopOnIdleEnd^> >> "%TEMP%\wifi_speedtest_task.xml"
echo       ^<RestartOnIdle^>false^</RestartOnIdle^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^</IdleSettings^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<AllowStartOnDemand^>true^</AllowStartOnDemand^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<Enabled^>true^</Enabled^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<Hidden^>false^</Hidden^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<RunOnlyIfIdle^>false^</RunOnlyIfIdle^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<WakeToRun^>false^</WakeToRun^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<ExecutionTimeLimit^>PT0S^</ExecutionTimeLimit^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<Priority^>7^</Priority^> >> "%TEMP%\wifi_speedtest_task.xml"
echo   ^</Settings^> >> "%TEMP%\wifi_speedtest_task.xml"
echo   ^<Actions Context="Author"^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^<Exec^> >> "%TEMP%\wifi_speedtest_task.xml"
echo       ^<Command^>"%BATCH_FILE%"^</Command^> >> "%TEMP%\wifi_speedtest_task.xml"
echo       ^<WorkingDirectory^>"%SCRIPT_DIR%"^</WorkingDirectory^> >> "%TEMP%\wifi_speedtest_task.xml"
echo     ^</Exec^> >> "%TEMP%\wifi_speedtest_task.xml"
echo   ^</Actions^> >> "%TEMP%\wifi_speedtest_task.xml"
echo ^</Task^> >> "%TEMP%\wifi_speedtest_task.xml"

echo Creating scheduled task...
schtasks /create /tn "WiFi Speedtest Script" /xml "%TEMP%\wifi_speedtest_task.xml" /f

if %errorlevel% equ 0 (
    echo.
    echo SUCCESS: Task created successfully!
    echo The script will now run automatically at startup.
    echo.
    echo To manage this task:
    echo - Open Task Scheduler (taskschd.msc)
    echo - Look for "WiFi Speedtest Script" in the Task Scheduler Library
    echo - You can enable/disable or modify the task from there
) else (
    echo.
    echo ERROR: Failed to create scheduled task.
    echo Make sure you're running this as Administrator.
)

REM Clean up temp file
del "%TEMP%\wifi_speedtest_task.xml" 2>nul
goto end

:startup_folder
echo.
echo Setting up Startup Folder method...
echo This will create a shortcut in the Windows Startup folder.
echo.

REM Get the startup folder path
set "STARTUP_FOLDER=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"

echo Creating shortcut in: %STARTUP_FOLDER%

REM Create a VBS script to create the shortcut
echo Set oWS = WScript.CreateObject("WScript.Shell") > "%TEMP%\create_shortcut.vbs"
echo sLinkFile = "%STARTUP_FOLDER%\WiFi Speedtest Script.lnk" >> "%TEMP%\create_shortcut.vbs"
echo Set oLink = oWS.CreateShortcut(sLinkFile) >> "%TEMP%\create_shortcut.vbs"
echo oLink.TargetPath = "%BATCH_FILE%" >> "%TEMP%\create_shortcut.vbs"
echo oLink.WorkingDirectory = "%SCRIPT_DIR%" >> "%TEMP%\create_shortcut.vbs"
echo oLink.Description = "WiFi Speedtest and Reconnection Script" >> "%TEMP%\create_shortcut.vbs"
echo oLink.Save >> "%TEMP%\create_shortcut.vbs"

REM Run the VBS script
cscript //nologo "%TEMP%\create_shortcut.vbs"

if exist "%STARTUP_FOLDER%\WiFi Speedtest Script.lnk" (
    echo.
    echo SUCCESS: Shortcut created in Startup folder!
    echo The script will now run when you log in to Windows.
    echo.
    echo To remove: Delete the shortcut from the Startup folder
) else (
    echo.
    echo ERROR: Failed to create shortcut.
)

REM Clean up temp file
del "%TEMP%\create_shortcut.vbs" 2>nul
goto end

:registry_run
echo.
echo Setting up Registry Run Key method...
echo This will add the script to the Windows Registry to run at startup.
echo.

echo Adding to Registry Run key...
reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run" /v "WiFi Speedtest Script" /t REG_SZ /d "\"%BATCH_FILE%\"" /f

if %errorlevel% equ 0 (
    echo.
    echo SUCCESS: Added to Registry Run key!
    echo The script will now run when you log in to Windows.
    echo.
    echo To remove: Run this command:
    echo reg delete "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run" /v "WiFi Speedtest Script" /f
) else (
    echo.
    echo ERROR: Failed to add to Registry.
)
goto end

:invalid_choice
echo.
echo Invalid choice. Please run the script again and select 1-4.
goto end

:exit
echo.
echo Exiting without making changes.
goto end

:end
echo.
echo Setup complete!
pause
