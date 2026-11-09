@echo off
rem Put movie.mp4 and movie-trailer.mp4 in a folder and drag the movie onto this. The trailer is optional.
rem It asks a few questions and makes the Jim's Movie Theater add-on in that folder.
rem Forgot the trailer? Drag movie-trailer.mp4 on its own and it can add just the trailer to that add-on.
rem You need ffmpeg and RAD Video Tools installed.
rem Or from a prompt: Make-JimsMovie.bat "D:\movies\nosferatu.mp4"
rem Anything after the video goes straight to Make-JimsMovie.ps1, like -Genre horror or -ModsDir "D:\mods".
setlocal

if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Make-JimsMovie.ps1" -Ask
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Make-JimsMovie.ps1" -Video "%~1" -Ask %2 %3 %4 %5 %6 %7 %8 %9
)

if errorlevel 1 echo. & echo Something went wrong, see above.
pause
