@echo off
title LLMCleaner
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0LLMCleaner.ps1" %*
if errorlevel 1 (
    echo.
    echo LLMCleaner could not start. / Nie udalo sie uruchomic LLMCleanera.
    pause
)
