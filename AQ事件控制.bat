@echo off
setlocal EnableExtensions
title CMaNGOS AQ Event Control

if /I "%~1"=="EnableCollection" goto direct
if /I "%~1"=="EnableTransportation" goto direct
if /I "%~1"=="EnableGong" goto direct
if /I "%~1"=="EnableTenHourWar" goto direct
if /I "%~1"=="Status" goto direct
if /I "%~1"=="DisableAll" goto direct

:menu
cls
echo ========================================
echo        CMaNGOS AQ Event Control
echo ========================================
echo  1. Event 120 - Collection
echo  2. Event 121 - Transportation
echo  3. Event 122 - Gong ready
echo  4. Event 123 - Original 10-hour war
echo  5. Status
echo  6. Disable AQ events
echo  0. Exit
echo ========================================
set "AQ_CHOICE="
set /p "AQ_CHOICE=Choice: "

if "%AQ_CHOICE%"=="1" call :run EnableCollection
if "%AQ_CHOICE%"=="2" call :run EnableTransportation
if "%AQ_CHOICE%"=="3" call :run EnableGong
if "%AQ_CHOICE%"=="4" call :run EnableTenHourWar
if "%AQ_CHOICE%"=="5" call :run Status
if "%AQ_CHOICE%"=="6" call :run DisableAll
if "%AQ_CHOICE%"=="0" exit /b 0
goto menu

:run
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0aq_event_control_launcher.ps1" -Action %1
echo.
pause
goto :eof

:direct
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0aq_event_control_launcher.ps1" -Action %~1
exit /b %errorlevel%
