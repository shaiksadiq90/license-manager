@echo off
REM Double-click to install the full License Manager DevOps toolchain.
REM Asks once for administrator rights, then runs scripts\setup-windows.ps1 and logs to setup-log.txt
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File \"%~dp0scripts\setup-windows.ps1\"'"
