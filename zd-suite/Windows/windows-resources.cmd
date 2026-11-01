@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows-resources.ps1" %*
set "setup_exit=%errorlevel%"
if not "%setup_exit%"=="0" echo Some applications could not be installed. Review the results above.
if "%~1"=="" pause
exit /b %setup_exit%
