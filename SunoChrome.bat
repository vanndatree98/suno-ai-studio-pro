@echo off
chcp 65001 >nul
title Suno AI Studio Pro - Modern Google Chrome Engine
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SunoChrome.ps1"
