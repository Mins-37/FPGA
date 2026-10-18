@echo off
setlocal
chcp 65001 >nul
echo This installs converter dependencies into this tool folder only.
if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" (
 "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" -m pip install --target "%~dp0runtime_lib" pillow imageio-ffmpeg==0.6.0
) else (
 py -3 -m pip install --target "%~dp0runtime_lib" pillow imageio-ffmpeg==0.6.0
)
pause
