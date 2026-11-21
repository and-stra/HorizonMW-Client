@echo off
rem Starts the MWX opencode bridge. Leave this window open while Claude is working.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bridge.ps1"
pause
