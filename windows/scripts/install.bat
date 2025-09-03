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

REM Function to create WiFi profile using simple netsh commands
:create_simple_profile
echo.
echo Creating WiFi profile for %SSID_NAME%...

REM Delete existing profile if it exists
netsh wlan delete profile name="%SSID_NAME%" >nul 2>&1

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

echo Profile creation command completed with return code: !errorlevel!

REM Verify profile was created
echo.
echo Verifying profile creation...
netsh wlan show profiles | findstr /i "%SSID_NAME%"
if !errorlevel! equ 0 (
    echo SUCCESS: Profile created and verified!
    echo.
    echo Profile details:
    netsh wlan show profile name="%SSID_NAME%" key=clear
) else (
    echo FAILED: Profile was not created.
    echo.
    echo Trying alternative method...
    netsh wlan add profile name="%SSID_NAME%" ssid="%SSID_NAME%"
    netsh wlan show profiles | findstr /i "%SSID_NAME%"
    if !errorlevel! equ 0 (
        echo SUCCESS: Profile created with alternative method!
    ) else (
        echo FAILED: All profile creation methods failed.
    )
)
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
    
    REM Check if profile exists, create if not
    echo.
    echo Checking if WiFi profile exists for %SSID_NAME%...
    netsh wlan show profiles | findstr /i "%SSID_NAME%" >nul
    if !errorlevel! equ 0 (
        echo WiFi profile for %SSID_NAME% already exists.
    ) else (
        echo WiFi profile for %SSID_NAME% not found. Creating profile...
        call :create_simple_profile
    )
    
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
    echo Connection command completed with return code: !errorlevel!
    
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
