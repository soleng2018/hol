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
:check_profile
echo Checking if WiFi profile exists for %SSID_NAME%...
netsh wlan show profiles | findstr /i "%SSID_NAME%" >nul
if !errorlevel! neq 0 (
    echo WiFi profile not found. Creating profile...
    if "%SSID_AUTH_TYPE%"=="PEAP" (
        netsh wlan add profile filename="%TEMP%\wifi_profile.xml"
    ) else if "%SSID_AUTH_TYPE%"=="PSK" (
        netsh wlan add profile filename="%TEMP%\wifi_profile.xml"
    ) else (
        echo Warning: Unknown auth type. Attempting basic connection...
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
    
    REM Disconnect from current WiFi
    echo Disconnecting from current WiFi...
    netsh wlan disconnect
    
    REM Wait a moment
    timeout /t 5 /nobreak >nul
    
    REM Check if profile exists, if not try to connect anyway
    call :check_profile
    
    REM Reconnect to WiFi - try different methods
    echo Attempting to connect to %SSID_NAME%...
    
    REM Method 1: Try connecting by profile name first
    netsh wlan connect name="%SSID_NAME%" >nul 2>&1
    if !errorlevel! neq 0 (
        echo Profile connection failed, trying SSID connection...
        REM Method 2: Try connecting by SSID
        netsh wlan connect ssid="%SSID_NAME%" >nul 2>&1
        if !errorlevel! neq 0 (
            echo SSID connection failed, trying interface connection...
            REM Method 3: Try connecting to any available network with this SSID
            for /f "tokens=*" %%i in ('netsh wlan show profiles ^| findstr /i "%SSID_NAME%"') do (
                set "profile_line=%%i"
                if "!profile_line!" neq "" (
                    echo Found profile: !profile_line!
                    netsh wlan connect name="%SSID_NAME%"
                )
            )
        )
    )
    
    REM Wait for connection to establish
    echo Waiting for WiFi connection to establish...
    timeout /t 10 /nobreak >nul
    
    REM Check if connected (wait a bit more for connection to establish)
    timeout /t 5 /nobreak >nul
    netsh wlan show interfaces | findstr /i "state.*connected" >nul
    if !errorlevel! equ 0 (
        echo WiFi connected successfully!
        
        REM Generate random speedtest time
        call :random %SPEEDTEST_MIN_TIME% %SPEEDTEST_MAX_TIME%
        set speedtest_time=!random_num!
        
        echo Waiting !speedtest_time! minutes before running speedtest...
        set /a speedtest_seconds=!speedtest_time! * 60
        timeout /t !speedtest_seconds! /nobreak >nul
        
        REM Run speedtest
        echo Running speedtest...
        if exist "speedtest.exe" (
            speedtest.exe
        ) else (
            echo Error: speedtest.exe not found in current directory!
        )
    ) else (
        echo Warning: WiFi connection failed!
        echo Current WiFi status:
        netsh wlan show interfaces
    )
    
    echo.
    echo Cycle completed. Starting next cycle...
    goto main_loop
