@echo off
rem Drag an .srt, .ass or .vtt, or an mkv with subtitles in it, onto this to add captions to a movie add-on you already made.
rem It looks for the add-on next to the subtitles and in your Zomboid\mods folder.
rem It asks if they go in the movie add-on or in another mod folder, like your own language pack.
rem You need ffmpeg installed.
rem Or from a prompt: Make-JimsCaptions.bat "D:\movies\nosferatu.srt"
rem Anything after the subtitles goes straight to Make-JimsCaptions.ps1, like -Offset -1.5 or -Language ES.
setlocal

if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Make-JimsCaptions.ps1" -Ask
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Make-JimsCaptions.ps1" -Subtitles "%~1" -Ask %2 %3 %4 %5 %6 %7 %8 %9
)

if errorlevel 1 echo. & echo Something went wrong, see above.
pause
