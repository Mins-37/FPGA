@echo off
setlocal
chcp 65001 >nul
if "%~1"=="" (
 echo Drag a video file with audio onto this command file.
 pause
 exit /b 1
)
if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" (
 "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" "%~dp0convert_av.py" "%~1" -o "%~dpn1.AVM" --seconds 14
) else (
 py -3 "%~dp0convert_av.py" "%~1" -o "%~dpn1.AVM" --seconds 14
)
pause
