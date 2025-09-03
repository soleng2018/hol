@echo off
setlocal enabledelayedexpansion

echo WiFi Diagnostic Tool
echo ====================
echo.

REM Load parameters from parameters.txt
for /f "usebackq tokens=1,2 delims==" %%a in ("parameters.txt") do (
    set "%%a=%%b"
)

REM Remove quotes from variables
set "SSID_NAME=%SSID_NAME:"=%"
set "SSID_AUTH_TYPE=%SSID_AUTH_TYPE:"=%"

echo Target SSID: %SSID_NAME%
echo Auth Type: %SSID_AUTH_TYPE%
echo.

echo 1. Current WiFi Interfaces:
echo ---------------------------
netsh wlan show interfaces
echo.

echo 2. Available WiFi Networks:
echo ---------------------------
netsh wlan show networks
echo.

echo 3. Existing WiFi Profiles:
echo --------------------------
netsh wlan show profiles
echo.

echo 4. Checking if target SSID is available:
echo ----------------------------------------
netsh wlan show networks | findstr /i "%SSID_NAME%"
if !errorlevel! equ 0 (
    echo SUCCESS: %SSID_NAME% is available
) else (
    echo WARNING: %SSID_NAME% not found in available networks
)
echo.

echo 5. Checking if profile exists for target SSID:
echo ----------------------------------------------
netsh wlan show profiles | findstr /i "%SSID_NAME%"
if !errorlevel! equ 0 (
    echo SUCCESS: Profile exists for %SSID_NAME%
    echo.
    echo Profile details:
    netsh wlan show profile name="%SSID_NAME%" key=clear
) else (
    echo WARNING: No profile found for %SSID_NAME%
)
echo.

echo 6. Testing manual connection:
echo -----------------------------
echo Attempting to connect to %SSID_NAME%...
netsh wlan connect name="%SSID_NAME%"
timeout /t 10 /nobreak >nul

echo.
echo Connection status after 10 seconds:
netsh wlan show interfaces | findstr /i "state"

echo.
echo Diagnostic complete!
pause
