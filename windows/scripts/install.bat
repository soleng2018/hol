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
set /a "random_num=%random% %% (%2 - %1 + 1) + %1"
goto :eof

REM Main loop
:main_loop
    REM Generate random reconnect time
    call :random %RECONNECT_MIN_TIME% %RECONNECT_MAX_TIME%
    set reconnect_time=!random_num!
    
    echo.
    echo Waiting !reconnect_time! minutes before reconnecting to WiFi...
    timeout /t !reconnect_time! /nobreak >nul
    
    REM Disconnect from current WiFi
    echo Disconnecting from current WiFi...
    netsh wlan disconnect
    
    REM Wait a moment
    timeout /t 5 /nobreak >nul
    
    REM Reconnect to WiFi based on auth type
    if "%SSID_AUTH_TYPE%"=="PEAP" (
        echo Reconnecting to %SSID_NAME% using PEAP authentication...
        netsh wlan connect name="%SSID_NAME%" ssid="%SSID_NAME%"
    ) else if "%SSID_AUTH_TYPE%"=="PSK" (
        echo Reconnecting to %SSID_NAME% using PSK authentication...
        netsh wlan connect name="%SSID_NAME%" ssid="%SSID_NAME%"
    ) else (
        echo Reconnecting to %SSID_NAME%...
        netsh wlan connect name="%SSID_NAME%" ssid="%SSID_NAME%"
    )
    
    REM Wait for connection to establish
    echo Waiting for WiFi connection to establish...
    timeout /t 10 /nobreak >nul
    
    REM Check if connected
    netsh wlan show interfaces | findstr "State" | findstr "connected" >nul
    if !errorlevel! equ 0 (
        echo WiFi connected successfully!
        
        REM Generate random speedtest time
        call :random %SPEEDTEST_MIN_TIME% %SPEEDTEST_MAX_TIME%
        set speedtest_time=!random_num!
        
        echo Waiting !speedtest_time! minutes before running speedtest...
        timeout /t !speedtest_time! /nobreak >nul
        
        REM Run speedtest
        echo Running speedtest...
        if exist "speedtest.exe" (
            speedtest.exe
        ) else (
            echo Error: speedtest.exe not found in current directory!
        )
    ) else (
        echo Warning: WiFi connection failed!
    )
    
    echo.
    echo Cycle completed. Starting next cycle...
    goto main_loop
