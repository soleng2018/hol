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
    echo Current WiFi status:
    netsh wlan show interfaces
    
    REM Disconnect from current WiFi
    echo.
    echo Disconnecting from current WiFi...
    netsh wlan disconnect
    
    REM Wait a moment
    timeout /t 3 /nobreak >nul
    
    REM Show available networks
    echo.
    echo Scanning for available networks...
    netsh wlan show profiles | findstr /i "%SSID_NAME%"
    
    REM Try to connect using the most reliable method
    echo.
    echo Attempting to connect to %SSID_NAME%...
    
    REM First, try to connect by profile name (most reliable)
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
        echo Attempting alternative connection methods...
        
        REM Try connecting by SSID only
        echo Trying SSID-only connection...
        netsh wlan connect ssid="%SSID_NAME%"
        timeout /t 10 /nobreak >nul
        
        REM Check again
        netsh wlan show interfaces | findstr /i "state.*connected" >nul
        if !errorlevel! equ 0 (
            echo WiFi connected on second attempt!
        ) else (
            echo WiFi connection still failed. Will retry in next cycle.
        )
    )
    
    echo.
    echo Cycle completed. Starting next cycle...
    goto main_loop
