@echo off
title Uninstalling Suno AI Music...
echo Removing shortcuts...
del /F /Q "%USERPROFILE%\Desktop\Suno AI Music.lnk" >nul 2>&1
rmdir /S /Q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Suno AI Music" >nul 2>&1
echo Cleaning registry...
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "SunoDesktop" /f >nul 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\SunoAIMusic" /f >nul 2>&1
echo Suno AI Music shortcuts and registry have been cleanly removed.
pause
