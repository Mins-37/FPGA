@echo off
setlocal
chcp 65001 >nul
if "%~1"=="" (
 echo Drag a GIF or video file onto this command file.
 pause
 exit /b 1
)
if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" (
 "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" "%~dp0convert_animation.py" "%~1" --fps 10 --seconds 10
) else (
 py -3 "%~dp0convert_animation.py" "%~1" --fps 10 --seconds 10
)
pause
