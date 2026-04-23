@echo off
chcp 65001 >nul
echo ============================================
echo   WIDE TETRIS - AI Environment Setup
echo ============================================
echo.

cd /d "%~dp0"

echo [1/3] Checking Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found. Please install Python 3.10+ and add to PATH.
    echo Download: https://www.python.org/downloads/
    pause
    exit /b 1
)
python --version

echo [2/3] Creating virtual environment (.venv)...
if exist .venv (
    echo        Virtual environment already exists, skipping.
) else (
    python -m venv .venv
    if errorlevel 1 (
        echo [ERROR] Failed to create virtual environment.
        pause
        exit /b 1
    )
)

echo [3/3] Installing dependencies...
.venv\Scripts\pip install -r requirements.txt --quiet
if errorlevel 1 (
    echo [ERROR] Failed to install dependencies. Check your network.
    pause
    exit /b 1
)

echo.
echo ============================================
echo   Setup complete!
echo   AI analysis is now available in-game.
echo ============================================
pause
