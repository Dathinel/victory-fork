@echo off
rem The window in front of scripts\play-4gb.ps1: pick the game, a profile and extra switches.
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0scripts\launcher-4gb.ps1"
