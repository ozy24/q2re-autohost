@echo off
title Q2RE Auto-Host Manager Launcher
echo Starting Q2RE Auto-Host Manager...
echo.

REM Check if AutoHotkey v2 is installed
where /q AutoHotkey.exe
if ERRORLEVEL 1 (
    echo ERROR: AutoHotkey v2 is not installed or not in PATH.
    echo Please install AutoHotkey v2 from https://www.autohotkey.com/
    echo.
    pause
    exit /b 1
)

REM Check if GUI script exists
if not exist "Q2REAutoHostGUI.ahk" (
    echo ERROR: Q2REAutoHostGUI.ahk not found in current directory.
    echo Please ensure all files are in the same folder.
    echo.
    pause
    exit /b 1
)

REM Launch the GUI
echo Launching GUI application...
start "" "Q2REAutoHostGUI.ahk"

REM Optional: Keep window open to show any errors
echo GUI launched successfully!
echo You can close this window now.
echo.
timeout /t 3 /nobreak >nul
exit /b 0