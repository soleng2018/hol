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

REM Function to check if WiFi profile exists
:check_and_create_profile
echo.
echo Checking WiFi profiles...
netsh wlan show profiles | findstr /i "%SSID_NAME%" >nul
if !errorlevel! equ 0 (
    echo WiFi profile for %SSID_NAME% already exists.
) else (
    echo WiFi profile for %SSID_NAME% not found. Creating profile...
    call :create_wifi_profile
)
goto :eof

REM Function to create WiFi profile
:create_wifi_profile
echo Creating WiFi profile for %SSID_NAME%...

if "%SSID_AUTH_TYPE%"=="PSK" (
    echo Creating PSK profile...
    call :create_psk_xml
    netsh wlan add profile filename="%TEMP%\wifi_profile_psk.xml"
) else if "%SSID_AUTH_TYPE%"=="PEAP" (
    echo Creating PEAP profile...
    call :create_peap_xml
    netsh wlan add profile filename="%TEMP%\wifi_profile_peap.xml"
) else (
    echo Creating basic profile...
    call :create_basic_xml
    netsh wlan add profile filename="%TEMP%\wifi_profile_basic.xml"
)

if !errorlevel! equ 0 (
    echo WiFi profile created successfully.
) else (
    echo Warning: Failed to create WiFi profile. Will try manual connection.
)
goto :eof

REM Function to create PSK profile XML
:create_psk_xml
echo ^<?xml version="1.0"?^> > "%TEMP%\wifi_profile_psk.xml"
echo ^<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"^> >> "%TEMP%\wifi_profile_psk.xml"
echo   ^<name^>%SSID_NAME%^</name^> >> "%TEMP%\wifi_profile_psk.xml"
echo   ^<SSIDConfig^> >> "%TEMP%\wifi_profile_psk.xml"
echo     ^<SSID^> >> "%TEMP%\wifi_profile_psk.xml"
echo       ^<name^>%SSID_NAME%^</name^> >> "%TEMP%\wifi_profile_psk.xml"
echo     ^</SSID^> >> "%TEMP%\wifi_profile_psk.xml"
echo   ^</SSIDConfig^> >> "%TEMP%\wifi_profile_psk.xml"
echo   ^<connectionType^>ESS^</connectionType^> >> "%TEMP%\wifi_profile_psk.xml"
echo   ^<connectionMode^>auto^</connectionMode^> >> "%TEMP%\wifi_profile_psk.xml"
echo   ^<MSM^> >> "%TEMP%\wifi_profile_psk.xml"
echo     ^<security^> >> "%TEMP%\wifi_profile_psk.xml"
echo       ^<authEncryption^> >> "%TEMP%\wifi_profile_psk.xml"
echo         ^<authentication^>WPA2PSK^</authentication^> >> "%TEMP%\wifi_profile_psk.xml"
echo         ^<encryption^>AES^</encryption^> >> "%TEMP%\wifi_profile_psk.xml"
echo         ^<useOneX^>false^</useOneX^> >> "%TEMP%\wifi_profile_psk.xml"
echo       ^</authEncryption^> >> "%TEMP%\wifi_profile_psk.xml"
echo       ^<sharedKey^> >> "%TEMP%\wifi_profile_psk.xml"
echo         ^<keyType^>passPhrase^</keyType^> >> "%TEMP%\wifi_profile_psk.xml"
echo         ^<protected^>false^</protected^> >> "%TEMP%\wifi_profile_psk.xml"
echo         ^<keyMaterial^>%PSK%^</keyMaterial^> >> "%TEMP%\wifi_profile_psk.xml"
echo       ^</sharedKey^> >> "%TEMP%\wifi_profile_psk.xml"
echo     ^</security^> >> "%TEMP%\wifi_profile_psk.xml"
echo   ^</MSM^> >> "%TEMP%\wifi_profile_psk.xml"
echo ^</WLANProfile^> >> "%TEMP%\wifi_profile_psk.xml"
goto :eof

REM Function to create PEAP profile XML
:create_peap_xml
echo ^<?xml version="1.0"?^> > "%TEMP%\wifi_profile_peap.xml"
echo ^<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"^> >> "%TEMP%\wifi_profile_peap.xml"
echo   ^<name^>%SSID_NAME%^</name^> >> "%TEMP%\wifi_profile_peap.xml"
echo   ^<SSIDConfig^> >> "%TEMP%\wifi_profile_peap.xml"
echo     ^<SSID^> >> "%TEMP%\wifi_profile_peap.xml"
echo       ^<name^>%SSID_NAME%^</name^> >> "%TEMP%\wifi_profile_peap.xml"
echo     ^</SSID^> >> "%TEMP%\wifi_profile_peap.xml"
echo   ^</SSIDConfig^> >> "%TEMP%\wifi_profile_peap.xml"
echo   ^<connectionType^>ESS^</connectionType^> >> "%TEMP%\wifi_profile_peap.xml"
echo   ^<connectionMode^>auto^</connectionMode^> >> "%TEMP%\wifi_profile_peap.xml"
echo   ^<MSM^> >> "%TEMP%\wifi_profile_peap.xml"
echo     ^<security^> >> "%TEMP%\wifi_profile_peap.xml"
echo       ^<authEncryption^> >> "%TEMP%\wifi_profile_peap.xml"
echo         ^<authentication^>WPA2^</authentication^> >> "%TEMP%\wifi_profile_peap.xml"
echo         ^<encryption^>AES^</encryption^> >> "%TEMP%\wifi_profile_peap.xml"
echo         ^<useOneX^>true^</useOneX^> >> "%TEMP%\wifi_profile_peap.xml"
echo       ^</authEncryption^> >> "%TEMP%\wifi_profile_peap.xml"
echo       ^<OneX xmlns="http://www.microsoft.com/networking/OneX/v1"^> >> "%TEMP%\wifi_profile_peap.xml"
echo         ^<authMode^>userOrMachine^</authMode^> >> "%TEMP%\wifi_profile_peap.xml"
echo         ^<EAPConfig^> >> "%TEMP%\wifi_profile_peap.xml"
echo           ^<EapHostConfig xmlns="http://www.microsoft.com/provisioning/EapHostConfig"^> >> "%TEMP%\wifi_profile_peap.xml"
echo             ^<EapMethod^> >> "%TEMP%\wifi_profile_peap.xml"
echo               ^<Type xmlns="http://www.microsoft.com/provisioning/EapCommon"^>25^</Type^> >> "%TEMP%\wifi_profile_peap.xml"
echo               ^<VendorId xmlns="http://www.microsoft.com/provisioning/EapCommon"^>0^</VendorId^> >> "%TEMP%\wifi_profile_peap.xml"
echo               ^<VendorType xmlns="http://www.microsoft.com/provisioning/EapCommon"^>0^</VendorType^> >> "%TEMP%\wifi_profile_peap.xml"
echo               ^<AuthorId xmlns="http://www.microsoft.com/provisioning/EapCommon"^>0^</AuthorId^> >> "%TEMP%\wifi_profile_peap.xml"
echo             ^</EapMethod^> >> "%TEMP%\wifi_profile_peap.xml"
echo             ^<Config xmlns="http://www.microsoft.com/provisioning/EapHostConfig"^> >> "%TEMP%\wifi_profile_peap.xml"
echo               ^<Eap xmlns="http://www.microsoft.com/provisioning/BaseEapConnectionPropertiesV1"^> >> "%TEMP%\wifi_profile_peap.xml"
echo                 ^<Type^>25^</Type^> >> "%TEMP%\wifi_profile_peap.xml"
echo                 ^<EapType xmlns="http://www.microsoft.com/provisioning/MsPeapConnectionPropertiesV1"^> >> "%TEMP%\wifi_profile_peap.xml"
echo                   ^<ServerValidation^> >> "%TEMP%\wifi_profile_peap.xml"
echo                     ^<DisableUserPromptForServerValidation^>false^</DisableUserPromptForServerValidation^> >> "%TEMP%\wifi_profile_peap.xml"
echo                     ^<ServerNames^>^</ServerNames^> >> "%TEMP%\wifi_profile_peap.xml"
echo                   ^</ServerValidation^> >> "%TEMP%\wifi_profile_peap.xml"
echo                   ^<FastReconnect^>true^</FastReconnect^> >> "%TEMP%\wifi_profile_peap.xml"
echo                   ^<InnerEapOptional^>false^</InnerEapOptional^> >> "%TEMP%\wifi_profile_peap.xml"
echo                   ^<Eap xmlns="http://www.microsoft.com/provisioning/BaseEapConnectionPropertiesV1"^> >> "%TEMP%\wifi_profile_peap.xml"
echo                     ^<Type^>26^</Type^> >> "%TEMP%\wifi_profile_peap.xml"
echo                     ^<EapType xmlns="http://www.microsoft.com/provisioning/MsChapV2ConnectionPropertiesV1"^> >> "%TEMP%\wifi_profile_peap.xml"
echo                       ^<UseWinLogonCredentials^>false^</UseWinLogonCredentials^> >> "%TEMP%\wifi_profile_peap.xml"
echo                     ^</EapType^> >> "%TEMP%\wifi_profile_peap.xml"
echo                   ^</Eap^> >> "%TEMP%\wifi_profile_peap.xml"
echo                   ^<EnableQuarantineChecks^>false^</EnableQuarantineChecks^> >> "%TEMP%\wifi_profile_peap.xml"
echo                   ^<RequireCryptoBinding^>false^</RequireCryptoBinding^> >> "%TEMP%\wifi_profile_peap.xml"
echo                   ^<PeapExtensions^> >> "%TEMP%\wifi_profile_peap.xml"
echo                     ^<PerformServerValidation xmlns="http://www.microsoft.com/provisioning/MsPeapConnectionPropertiesV2"^>true^</PerformServerValidation^> >> "%TEMP%\wifi_profile_peap.xml"
echo                     ^<AcceptServerName xmlns="http://www.microsoft.com/provisioning/MsPeapConnectionPropertiesV2"^>true^</AcceptServerName^> >> "%TEMP%\wifi_profile_peap.xml"
echo                   ^</PeapExtensions^> >> "%TEMP%\wifi_profile_peap.xml"
echo                 ^</EapType^> >> "%TEMP%\wifi_profile_peap.xml"
echo               ^</Eap^> >> "%TEMP%\wifi_profile_peap.xml"
echo             ^</Config^> >> "%TEMP%\wifi_profile_peap.xml"
echo           ^</EapHostConfig^> >> "%TEMP%\wifi_profile_peap.xml"
echo         ^</EAPConfig^> >> "%TEMP%\wifi_profile_peap.xml"
echo       ^</OneX^> >> "%TEMP%\wifi_profile_peap.xml"
echo     ^</security^> >> "%TEMP%\wifi_profile_peap.xml"
echo   ^</MSM^> >> "%TEMP%\wifi_profile_peap.xml"
echo ^</WLANProfile^> >> "%TEMP%\wifi_profile_peap.xml"
goto :eof

REM Function to create basic profile XML
:create_basic_xml
echo ^<?xml version="1.0"?^> > "%TEMP%\wifi_profile_basic.xml"
echo ^<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"^> >> "%TEMP%\wifi_profile_basic.xml"
echo   ^<name^>%SSID_NAME%^</name^> >> "%TEMP%\wifi_profile_basic.xml"
echo   ^<SSIDConfig^> >> "%TEMP%\wifi_profile_basic.xml"
echo     ^<SSID^> >> "%TEMP%\wifi_profile_basic.xml"
echo       ^<name^>%SSID_NAME%^</name^> >> "%TEMP%\wifi_profile_basic.xml"
echo     ^</SSID^> >> "%TEMP%\wifi_profile_basic.xml"
echo   ^</SSIDConfig^> >> "%TEMP%\wifi_profile_basic.xml"
echo   ^<connectionType^>ESS^</connectionType^> >> "%TEMP%\wifi_profile_basic.xml"
echo   ^<connectionMode^>auto^</connectionMode^> >> "%TEMP%\wifi_profile_basic.xml"
echo   ^<MSM^> >> "%TEMP%\wifi_profile_basic.xml"
echo     ^<security^> >> "%TEMP%\wifi_profile_basic.xml"
echo       ^<authEncryption^> >> "%TEMP%\wifi_profile_basic.xml"
echo         ^<authentication^>open^</authentication^> >> "%TEMP%\wifi_profile_basic.xml"
echo         ^<encryption^>none^</encryption^> >> "%TEMP%\wifi_profile_basic.xml"
echo         ^<useOneX^>false^</useOneX^> >> "%TEMP%\wifi_profile_basic.xml"
echo       ^</authEncryption^> >> "%TEMP%\wifi_profile_basic.xml"
echo     ^</security^> >> "%TEMP%\wifi_profile_basic.xml"
echo   ^</MSM^> >> "%TEMP%\wifi_profile_basic.xml"
echo ^</WLANProfile^> >> "%TEMP%\wifi_profile_basic.xml"
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
    
    REM Show current WiFi status
    echo.
    echo Current WiFi status:
    netsh wlan show interfaces
    
    REM Check and create profile if needed
    call :check_and_create_profile
    
    REM Disconnect from current WiFi
    echo.
    echo Disconnecting from current WiFi...
    netsh wlan disconnect
    
    REM Wait a moment
    timeout /t 3 /nobreak >nul
    
    REM Try to connect
    echo.
    echo Attempting to connect to %SSID_NAME%...
    
    REM Method 1: Connect by profile name
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
        echo Available networks:
        netsh wlan show profiles
        echo.
        echo Available SSIDs:
        netsh wlan show networks
    )
    
    echo.
    echo Cycle completed. Starting next cycle...
    goto main_loop
