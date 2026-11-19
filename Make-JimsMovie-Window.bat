@echo off
rem conhost so windows terminal never gets it, -WindowStyle Hidden kills the window there sometimes
rem drag a movie onto this and it gets filled in. goto instead of if ( ) since movie names have ( ) in them
if "%~1"=="" goto nothingDropped
start "" conhost.exe powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Make-JimsMovie-Window.ps1" -Video "%~1"
goto :eof
:nothingDropped
start "" conhost.exe powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Make-JimsMovie-Window.ps1"
