@echo off
setlocal enabledelayedexpansion

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

echo Starting WiFi reconnection and speedtest script...
echo SSID: %SSID_NAME%
echo Auth Type: %SSID_AUTH_TYPE%

REM Function to generate random number between min and max
:random
if "%1"=="" goto :eof
if "%2"=="" goto :eof
set /a "random_num=%random% %% (%2 - %1 + 1) + %1"
goto :eof

REM Function to ensure WiFi profile exists
:ensure_profile_exists
echo.
echo Checking if WiFi profile exists for %SSID_NAME%...
netsh wlan show profiles | findstr /i "%SSID_NAME%" >nul
if !errorlevel! equ 0 (
    echo WiFi profile for %SSID_NAME% already exists.
    goto :eof
)

echo WiFi profile for %SSID_NAME% not found. Creating profile...

REM Create a simple profile using netsh commands instead of XML
if "%SSID_AUTH_TYPE%"=="PSK" (
    echo Creating PSK profile...
    netsh wlan add profile filename="%TEMP%\wifi_psk.xml"
    if !errorlevel! equ 0 (
        echo PSK profile created successfully.
    ) else (
        echo Failed to create PSK profile. Trying alternative method...
        netsh wlan add profile name="%SSID_NAME%" ssid="%SSID_NAME%" keyMaterial="%PSK%" keyUsage=persistent
    )
) else if "%SSID_AUTH_TYPE%"=="PEAP" (
    echo Creating PEAP profile...
    netsh wlan add profile filename="%TEMP%\wifi_peap.xml"
    if !errorlevel! equ 0 (
        echo PEAP profile created successfully.
    ) else (
        echo Failed to create PEAP profile. Trying alternative method...
        netsh wlan add profile name="%SSID_NAME%" ssid="%SSID_NAME%" userData="%PEAP_USERNAME%"
    )
) else (
    echo Creating basic profile...
    netsh wlan add profile name="%SSID_NAME%" ssid="%SSID_NAME%"
)

REM Verify profile was created
netsh wlan show profiles | findstr /i "%SSID_NAME%" >nul
if !errorlevel! equ 0 (
    echo SUCCESS: WiFi profile created and verified.
) else (
    echo WARNING: WiFi profile creation may have failed.
)
goto :eof

REM Create PSK XML profile
:create_psk_xml
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
goto :eof

REM Create PEAP XML profile
:create_peap_xml
echo ^<?xml version="1.0"?^> > "%TEMP%\wifi_peap.xml"
echo ^<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"^> >> "%TEMP%\wifi_peap.xml"
echo   ^<name^>%SSID_NAME%^</name^> >> "%TEMP%\wifi_peap.xml"
echo   ^<SSIDConfig^> >> "%TEMP%\wifi_peap.xml"
echo     ^<SSID^> >> "%TEMP%\wifi_peap.xml"
echo       ^<name^>%SSID_NAME%^</name^> >> "%TEMP%\wifi_peap.xml"
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
goto :eof

REM Main loop
:main_loop
    REM Generate random reconnect time
    echo DEBUG: RECONNECT_MIN_TIME=%RECONNECT_MIN_TIME%, RECONNECT_MAX_TIME=%RECONNECT_MAX_TIME%
    call :random %RECONNECT_MIN_TIME% %RECONNECT_MAX_TIME%
    set reconnect_time=!random_num!
    echo DEBUG: Generated reconnect_time=!reconnect_time!
    
    echo.
    echo Waiting !reconnect_time! minutes before reconnecting to WiFi...
    set /a reconnect_seconds=!reconnect_time! * 60
    timeout /t !reconnect_seconds! /nobreak >nul
    
    REM Ensure profile exists before attempting connection
    call :ensure_profile_exists
    
    REM Show current WiFi status
    echo.
    echo Current WiFi status:
    netsh wlan show interfaces
    
    REM Disconnect from current WiFi
    echo.
    echo Disconnecting from current WiFi...
    netsh wlan disconnect
    
    REM Wait a moment
    timeout /t 3 /nobreak >nul
    
    REM Try to connect
    echo.
    echo Attempting to connect to %SSID_NAME%...
    
    REM Connect by profile name
    netsh wlan connect name="%SSID_NAME%"
    
    REM Wait for connection to establish
    echo Waiting for WiFi connection to establish...
    timeout /t 15 /nobreak >nul
    
    REM Check connection status
    echo.
    echo Checking connection status...
    netsh wlan show interfaces | findstr /i "state"
    
    REM Check if connected
    netsh wlan show interfaces | findstr /i "state.*connected" >nul
    if !errorlevel! equ 0 (
        echo.
        echo WiFi connected successfully!
        
        REM Generate random speedtest time
        call :random %SPEEDTEST_MIN_TIME% %SPEEDTEST_MAX_TIME%
        set speedtest_time=!random_num!
        
        echo Waiting !speedtest_time! minutes before running speedtest...
        set /a speedtest_seconds=!speedtest_time! * 60
        timeout /t !speedtest_seconds! /nobreak >nul
        
        REM Run speedtest
        echo.
        echo Running speedtest...
        if exist "speedtest.exe" (
            speedtest.exe
        ) else (
            echo Error: speedtest.exe not found in current directory!
        )
    ) else (
        echo.
        echo Warning: WiFi connection failed!
        echo.
        echo Available profiles:
        netsh wlan show profiles
        echo.
        echo Available networks:
        netsh wlan show networks
    )
    
    echo.
    echo Cycle completed. Starting next cycle...
    goto main_loop
