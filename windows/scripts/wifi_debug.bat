@echo off
setlocal enabledelayedexpansion

echo WiFi Profile Creation Debug Tool
echo ================================
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
echo PSK: %PSK%
echo PEAP Username: %PEAP_USERNAME%
echo PEAP Password: %PEAP_PASSWORD%
echo.

echo Step 1: Checking current profiles...
echo ------------------------------------
netsh wlan show profiles | findstr /i "%SSID_NAME%"
if !errorlevel! equ 0 (
    echo Profile already exists!
    goto :end
) else (
    echo Profile does NOT exist. Will create it.
)
echo.

echo Step 2: Creating profile based on auth type...
echo ----------------------------------------------
echo Auth type is: "%SSID_AUTH_TYPE%"

if "%SSID_AUTH_TYPE%"=="PSK" (
    echo Creating PSK profile...
    call :create_psk_xml
    echo XML file created. Contents:
    type "%TEMP%\wifi_psk.xml"
    echo.
    echo Adding profile to Windows...
    netsh wlan add profile filename="%TEMP%\wifi_psk.xml"
    echo netsh return code: !errorlevel!
) else if "%SSID_AUTH_TYPE%"=="PEAP" (
    echo Creating PEAP profile...
    call :create_peap_xml
    echo XML file created. Contents:
    type "%TEMP%\wifi_peap.xml"
    echo.
    echo Adding profile to Windows...
    netsh wlan add profile filename="%TEMP%\wifi_peap.xml"
    echo netsh return code: !errorlevel!
) else (
    echo Creating basic profile...
    netsh wlan add profile name="%SSID_NAME%" ssid="%SSID_NAME%"
    echo netsh return code: !errorlevel!
)
echo.

echo Step 3: Verifying profile was created...
echo ---------------------------------------
netsh wlan show profiles | findstr /i "%SSID_NAME%"
if !errorlevel! equ 0 (
    echo SUCCESS: Profile created and verified!
    echo.
    echo Profile details:
    netsh wlan show profile name="%SSID_NAME%" key=clear
) else (
    echo FAILED: Profile was not created.
    echo.
    echo All current profiles:
    netsh wlan show profiles
)
echo.

echo Step 4: Testing connection...
echo ----------------------------
echo Attempting to connect...
netsh wlan connect name="%SSID_NAME%"
timeout /t 10 /nobreak >nul
echo.
echo Connection status:
netsh wlan show interfaces | findstr /i "state"

goto :end

REM Create PSK XML profile
:create_psk_xml
echo Creating PSK XML file at: %TEMP%\wifi_psk.xml
echo ^<?xml version="1.0"?^> > "%TEMP%\wifi_psk.xml"
echo ^<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"^> >> "%TEMP%\wifi_psk.xml"
echo   ^<name^>%SSID_NAME%^</name^> >> "%TEMP%\wifi_psk.xml"
echo   ^<SSIDConfig^> >> "%TEMP%\wifi_psk.xml"
echo     ^<SSID^> >> "%TEMP%\wifi_psk.xml"
echo       ^<name^>%SSID_NAME%^</name^> >> "%TEMP%\wifi_psk.xml"
echo     ^</SSID^> >> "%TEMP%\wifi_psk.xml"
echo   ^</SSIDConfig^> >> "%TEMP%\wifi_psk.xml"
echo   ^<connectionType^>ESS^</connectionType^> >> "%TEMP%\wifi_psk.xml"
echo   ^<connectionMode^>auto^</connectionMode^> >> "%TEMP%\wifi_psk.xml"
echo   ^<MSM^> >> "%TEMP%\wifi_psk.xml"
echo     ^<security^> >> "%TEMP%\wifi_psk.xml"
echo       ^<authEncryption^> >> "%TEMP%\wifi_psk.xml"
echo         ^<authentication^>WPA2PSK^</authentication^> >> "%TEMP%\wifi_psk.xml"
echo         ^<encryption^>AES^</encryption^> >> "%TEMP%\wifi_psk.xml"
echo         ^<useOneX^>false^</useOneX^> >> "%TEMP%\wifi_psk.xml"
echo       ^</authEncryption^> >> "%TEMP%\wifi_psk.xml"
echo       ^<sharedKey^> >> "%TEMP%\wifi_psk.xml"
echo         ^<keyType^>passPhrase^</keyType^> >> "%TEMP%\wifi_psk.xml"
echo         ^<protected^>false^</protected^> >> "%TEMP%\wifi_psk.xml"
echo         ^<keyMaterial^>%PSK%^</keyMaterial^> >> "%TEMP%\wifi_psk.xml"
echo       ^</sharedKey^> >> "%TEMP%\wifi_psk.xml"
echo     ^</security^> >> "%TEMP%\wifi_psk.xml"
echo   ^</MSM^> >> "%TEMP%\wifi_psk.xml"
echo ^</WLANProfile^> >> "%TEMP%\wifi_psk.xml"
echo PSK XML file created successfully.
goto :eof

REM Create PEAP XML profile
:create_peap_xml
echo Creating PEAP XML file at: %TEMP%\wifi_peap.xml
echo ^<?xml version="1.0"?^> > "%TEMP%\wifi_peap.xml"
echo ^<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"^> >> "%TEMP%\wifi_peap.xml"
echo   ^<name^>%SSID_NAME%^</name^> >> "%TEMP%\wifi_peap.xml"
echo   ^<SSIDConfig^> >> "%TEMP%\wifi_peap.xml"
echo     ^<SSID^> >> "%TEMP%\wifi_peap.xml"
echo       ^<name^>%SSID_NAME%^</name^> >> "%TEMP%\wifi_psk.xml"
echo     ^</SSID^> >> "%TEMP%\wifi_peap.xml"
echo   ^</SSIDConfig^> >> "%TEMP%\wifi_peap.xml"
echo   ^<connectionType^>ESS^</connectionType^> >> "%TEMP%\wifi_peap.xml"
echo   ^<connectionMode^>auto^</connectionMode^> >> "%TEMP%\wifi_peap.xml"
echo   ^<MSM^> >> "%TEMP%\wifi_peap.xml"
echo     ^<security^> >> "%TEMP%\wifi_peap.xml"
echo       ^<authEncryption^> >> "%TEMP%\wifi_peap.xml"
echo         ^<authentication^>WPA2^</authentication^> >> "%TEMP%\wifi_peap.xml"
echo         ^<encryption^>AES^</encryption^> >> "%TEMP%\wifi_peap.xml"
echo         ^<useOneX^>true^</useOneX^> >> "%TEMP%\wifi_peap.xml"
echo       ^</authEncryption^> >> "%TEMP%\wifi_peap.xml"
echo     ^</security^> >> "%TEMP%\wifi_peap.xml"
echo   ^</MSM^> >> "%TEMP%\wifi_peap.xml"
echo ^</WLANProfile^> >> "%TEMP%\wifi_peap.xml"
echo PEAP XML file created successfully.
goto :eof

:end
echo.
echo Debug complete!
pause
