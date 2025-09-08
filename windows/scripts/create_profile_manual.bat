@echo off
setlocal enabledelayedexpansion

echo Manual WiFi Profile Creation Tool
echo =================================
echo.

REM Load parameters from parameters.txt
for /f "usebackq tokens=1,2 delims==" %%a in ("parameters.txt") do (
    set "%%a=%%b"
)

REM Remove quotes from variables
set "SSID_NAME=%SSID_NAME:"=%"
set "SSID_AUTH_TYPE=%SSID_AUTH_TYPE:"=%"
set "PEAP_USERNAME=%PEAP_USERNAME:"=%"
set "PEAP_PASSWORD=%PEAP_PASSWORD:"=%"
set "PSK=%PSK:"=%"

echo Target SSID: %SSID_NAME%
echo Auth Type: %SSID_AUTH_TYPE%
echo.

echo Step 1: Deleting any existing profile...
netsh wlan delete profile name="%SSID_NAME%" >nul 2>&1
echo.

echo Step 2: Creating new profile...
if "%SSID_AUTH_TYPE%"=="PSK" (
    echo Creating PSK profile with password...
    netsh wlan add profile name="%SSID_NAME%" ssid="%SSID_NAME%" keyMaterial="%PSK%" keyUsage=persistent
) else if "%SSID_AUTH_TYPE%"=="PEAP" (
    echo Creating PEAP profile...
    netsh wlan add profile name="%SSID_NAME%" ssid="%SSID_NAME%" userData="%PEAP_USERNAME%"
) else (
    echo Creating basic open profile...
    netsh wlan add profile name="%SSID_NAME%" ssid="%SSID_NAME%"
)

echo Profile creation return code: !errorlevel!
echo.

echo Step 3: Verifying profile...
netsh wlan show profiles | findstr /i "%SSID_NAME%"
if !errorlevel! equ 0 (
    echo SUCCESS: Profile created!
    echo.
    echo Profile details:
    netsh wlan show profile name="%SSID_NAME%" key=clear
) else (
    echo FAILED: Profile not created.
)
echo.

echo Step 4: Testing connection...
echo Attempting to connect...
netsh wlan connect name="%SSID_NAME%"
timeout /t 10 /nobreak >nul
echo.
echo Connection status:
netsh wlan show interfaces | findstr /i "state"

echo.
echo Manual profile creation complete!
pause
