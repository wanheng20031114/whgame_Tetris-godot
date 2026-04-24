@echo off
setlocal

title WIDE TETRIS AI Setup
cd /d "%~dp0"

echo ============================================
echo   WIDE TETRIS - AI Environment Setup
echo ============================================
echo.
echo This window installs the local Python AI runtime.
echo.

set "PYTHON_CMD="

echo [1/4] Checking Python...
py -3 --version >nul 2>&1
if not errorlevel 1 (
    set "PYTHON_CMD=py -3"
) else (
    python --version >nul 2>&1
    if not errorlevel 1 (
        set "PYTHON_CMD=python"
    )
)

if not defined PYTHON_CMD (
    echo.
    echo [ERROR] Python 3 was not found.
    echo Please install Python 3.10 or newer and enable "Add python.exe to PATH".
    echo Download: https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)

%PYTHON_CMD% --version
echo.

echo [2/4] Creating virtual environment...
if exist ".venv\Scripts\python.exe" (
    echo Virtual environment already exists.
) else (
    %PYTHON_CMD% -m venv .venv
    if errorlevel 1 (
        echo.
        echo [ERROR] Failed to create the virtual environment.
        echo.
        pause
        exit /b 1
    )
)
echo.

echo [3/4] Upgrading pip...
".venv\Scripts\python.exe" -m pip install --upgrade pip --progress-bar on
if errorlevel 1 (
    echo.
    echo [ERROR] Failed to upgrade pip.
    echo.
    pause
    exit /b 1
)
echo.

echo [4/4] Installing AI dependencies...
".venv\Scripts\python.exe" -m pip install -r requirements.txt --progress-bar on
if errorlevel 1 (
    echo.
    echo [ERROR] Failed to install dependencies.
    echo Check your network connection, then run this file again.
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================
echo   Setup complete.
echo   AI analysis is now available in-game.
echo ============================================
echo.
pause
exit /b 0
