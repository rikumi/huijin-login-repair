@echo off
setlocal EnableExtensions DisableDelayedExpansion
call :main %*
set "APPLY_RESULT=%errorlevel%"
echo.
pause
exit /b %APPLY_RESULT%
:main
if not "%~2"=="" goto usage
set "SERIAL=%~1"
set "SELECTED_STATE="
set "BEFORE="
set "DIRECT="
if not defined ADB set "ADB=adb.exe"
if exist "%~dp0adb.exe" set "ADB=%~dp0adb.exe"
set "PAYLOAD=%~dp0payload"
set "REMOTE=/sdcard/Android/data/com.kiif.huijin/files/yoo/HotCode/BundleFiles/aa/aa113c7ee32454536ea53acabdae46f4"
set "ORIGINAL=95c6f26348ebf74734590acc1421157cde8feaa58475f4e27cfd445d62635542"
set "PATCHED=e7b5da492dcac2384a2df5e5fac23ed07cfe95f8ecccb5ec0dd3cc5a7d8b1757"
set "INFO=e33bc049aa76be1513bdc43f17be65f9b7e993a4a98c94b3c88d6777444dc1e1"
"%ADB%" version >nul 2>&1
if errorlevel 1 (echo ERROR: adb.exe was not found. Put it in PATH or beside this script. & exit /b 1)
call :hash "%PAYLOAD%\hotfix-patched.bundle" HASH
if errorlevel 1 goto bad_payload
if /i not "%HASH%"=="%PATCHED%" goto bad_payload
call :hash "%PAYLOAD%\hotfix-info.bin" HASH
if errorlevel 1 goto bad_payload
if /i not "%HASH%"=="%INFO%" goto bad_payload
:new_backup
set "BACKUP=%~dp0backups\%RANDOM%-%RANDOM%"
if exist "%BACKUP%" goto new_backup
mkdir "%BACKUP%" || exit /b 1
set "REMOTE_TMP=/data/local/tmp/huijin-apply-%RANDOM%-%RANDOM%"
if defined SERIAL goto device_selected
"%ADB%" devices >"%BACKUP%\devices.txt"
if errorlevel 1 goto failed
set "DEVICE_COUNT=0"
for /f "usebackq skip=1 tokens=1,2" %%S in ("%BACKUP%\devices.txt") do call :add_device "%%S" "%%T"
if "%DEVICE_COUNT%"=="0" (echo ERROR: No devices found. Connect a phone and enable USB debugging. & goto failed)
if not "%DEVICE_COUNT%"=="1" goto device_menu
set "SERIAL=%DEVICE_1%"
set "SELECTED_STATE=%STATE_1%"
echo One device found. Selected: %SERIAL%
goto device_selected
:device_menu
echo Connected devices:
for /l %%N in (1,1,%DEVICE_COUNT%) do call :show_device %%N
:device_prompt
set "DEVICE_CHOICE="
set /p "DEVICE_CHOICE=Enter device number: "
set "SERIAL="
for /l %%N in (1,1,%DEVICE_COUNT%) do call :match_choice %%N
if defined SERIAL goto device_selected
echo Invalid selection. Enter a number from the list.
goto device_prompt
:device_selected
if defined SELECTED_STATE if not "%SELECTED_STATE%"=="device" (echo ERROR: Selected device is offline or not authorized. Check USB debugging authorization. & goto failed)
echo %SERIAL%>"%BACKUP%\device.txt"
"%ADB%" -s "%SERIAL%" get-state >"%BACKUP%\state.txt" 2>nul
if errorlevel 1 goto failed
"%ADB%" -s "%SERIAL%" shell am get-current-user >"%BACKUP%\user.txt"
findstr /x "0" "%BACKUP%\user.txt" >nul || goto failed
"%ADB%" -s "%SERIAL%" shell dumpsys package com.kiif.huijin >"%BACKUP%\package.txt"
set "VERSION_OK="
set "CODE_OK="
for /f "tokens=2 delims== " %%V in ('findstr /c:"versionName=" "%BACKUP%\package.txt"') do if "%%V"=="1.6.0" set "VERSION_OK=1"
for /f "tokens=2 delims== " %%V in ('findstr /c:"versionCode=" "%BACKUP%\package.txt"') do if "%%V"=="7" set "CODE_OK=1"
if not defined VERSION_OK goto unsupported
if not defined CODE_OK goto unsupported
set "DIRECT=1"
call :root "id" >"%BACKUP%\root.txt" 2>nul
findstr /c:"uid=0(" "%BACKUP%\root.txt" >nul && goto root_ready
set "DIRECT=0"
call :root "id" >"%BACKUP%\root.txt" 2>nul
findstr /c:"uid=0(" "%BACKUP%\root.txt" >nul || goto no_root
:root_ready
call :root "test -f /sdcard/Android/data/com.kiif.huijin/files/yoo/HotCode/ManifestFiles/HotCode_1.0.27.bytes"
if errorlevel 1 goto unsupported
set "HAD_DATA=0"
set "HAD_INFO=0"
call :root "test -f %REMOTE%/__data"
if errorlevel 1 goto check_info
set "HAD_DATA=1"
call :pull "%REMOTE%/__data" "%BACKUP%\hotfix-before.bundle"
if errorlevel 1 goto failed
call :hash "%BACKUP%\hotfix-before.bundle" BEFORE
if errorlevel 1 goto failed
if /i "%BEFORE%"=="%ORIGINAL%" goto check_info
if /i not "%BEFORE%"=="%PATCHED%" goto unsupported
:check_info
call :root "test -f %REMOTE%/__info"
if errorlevel 1 goto ready
set "HAD_INFO=1"
call :pull "%REMOTE%/__info" "%BACKUP%\hotfix-before.info"
if errorlevel 1 goto failed
call :hash "%BACKUP%\hotfix-before.info" HASH
if errorlevel 1 goto failed
if /i not "%HASH%"=="%INFO%" goto unsupported
if /i "%BEFORE%"=="%PATCHED%" goto already
:ready
echo had_data=%HAD_DATA%>"%BACKUP%\before.txt"
echo had_info=%HAD_INFO%>>"%BACKUP%\before.txt"
"%ADB%" -s "%SERIAL%" shell am force-stop com.kiif.huijin
if errorlevel 1 goto failed
echo Applying patch to %SERIAL%...
call :root "mkdir -p %REMOTE%"
if errorlevel 1 goto failed
call :put "%PAYLOAD%\hotfix-patched.bundle" "%REMOTE%/__data"
if errorlevel 1 goto rollback
call :put "%PAYLOAD%\hotfix-info.bin" "%REMOTE%/__info"
if errorlevel 1 goto rollback
call :pull "%REMOTE%/__data" "%BACKUP%\verify.bundle"
if errorlevel 1 goto rollback
call :hash "%BACKUP%\verify.bundle" HASH
if errorlevel 1 goto rollback
if /i not "%HASH%"=="%PATCHED%" goto rollback
call :pull "%REMOTE%/__info" "%BACKUP%\verify.info"
if errorlevel 1 goto rollback
call :hash "%BACKUP%\verify.info" HASH
if errorlevel 1 goto rollback
if /i not "%HASH%"=="%INFO%" goto rollback
echo verified>"%BACKUP%\applied.txt"
call :root "rm -f %REMOTE_TMP%" >nul 2>&1
echo Patch applied and verified. Backup: "%BACKUP%"
"%ADB%" -s "%SERIAL%" shell monkey -p com.kiif.huijin -c android.intent.category.LAUNCHER 1 >nul 2>&1
if errorlevel 1 echo Game launch failed. Start the game manually.
exit /b 0
:already
call :root "rm -f %REMOTE_TMP%" >nul 2>&1
echo Already patched. Existing saves were not changed.
exit /b 0
:rollback
echo ERROR: Apply failed. Restoring original cache files...
set "ROLLBACK_FAILED="
if "%HAD_DATA%"=="1" (call :put "%BACKUP%\hotfix-before.bundle" "%REMOTE%/__data") else (call :root "rm -f %REMOTE%/__data")
if errorlevel 1 set "ROLLBACK_FAILED=1"
if "%HAD_INFO%"=="1" (call :put "%BACKUP%\hotfix-before.info" "%REMOTE%/__info") else (call :root "rm -f %REMOTE%/__info")
if errorlevel 1 set "ROLLBACK_FAILED=1"
if defined ROLLBACK_FAILED echo Automatic restore failed. Keep the backup and reconnect the device.
if not defined ROLLBACK_FAILED echo Original cache files restored. Game remains stopped.
goto failed
:unsupported
echo ERROR: Requires client 1.6.0, versionCode 7, HotCode 1.0.27 and a recognized cache.
goto failed
:no_root
echo ERROR: Root is required. Allow su access on the selected phone.
:failed
if defined DIRECT call :root "rm -f %REMOTE_TMP%" >nul 2>&1
echo Apply did not complete. Retain backup: "%BACKUP%"
exit /b 1
:bad_payload
echo ERROR: Payload is missing or corrupted. No device files were changed.
exit /b 1
:usage
echo Double-click apply.bat to select a connected device.
echo Optional: apply.bat DEVICE_SERIAL
echo Example: apply.bat 127.0.0.1:16448
echo Requires Root and Huijin 1.6.0 / HotCode 1.0.27.
exit /b 2
:add_device
if "%~1"=="*" exit /b 0
if "%~2"=="" exit /b 0
set /a DEVICE_COUNT+=1 >nul
set "DEVICE_%DEVICE_COUNT%=%~1"
set "STATE_%DEVICE_COUNT%=%~2"
exit /b 0
:show_device
for /f "tokens=1,* delims==" %%A in ('set DEVICE_%~1') do if "%%A"=="DEVICE_%~1" echo [%~1] %%B
for /f "tokens=1,* delims==" %%A in ('set STATE_%~1') do if "%%A"=="STATE_%~1" echo     State: %%B
exit /b 0
:match_choice
(set DEVICE_CHOICE) 2>nul | findstr /l /x /c:"DEVICE_CHOICE=%~1" >nul
if errorlevel 1 exit /b 0
for /f "tokens=1,* delims==" %%A in ('set DEVICE_%~1') do if "%%A"=="DEVICE_%~1" set "SERIAL=%%B"
for /f "tokens=1,* delims==" %%A in ('set STATE_%~1') do if "%%A"=="STATE_%~1" set "SELECTED_STATE=%%B"
exit /b 0
:root
if "%DIRECT%"=="1" ("%ADB%" -s "%SERIAL%" shell "%~1") else ("%ADB%" -s "%SERIAL%" shell "su -c '%~1'")
exit /b %errorlevel%
:pull
call :root "cp %~1 %REMOTE_TMP% && chmod 644 %REMOTE_TMP%"
if errorlevel 1 exit /b 1
"%ADB%" -s "%SERIAL%" pull "%REMOTE_TMP%" "%~2" >nul 2>&1
exit /b %errorlevel%
:put
"%ADB%" -s "%SERIAL%" push "%~1" "%REMOTE_TMP%" >nul 2>&1
if errorlevel 1 exit /b 1
call :root "cp %REMOTE_TMP% %~2 && chmod 664 %~2 && sync"
exit /b %errorlevel%
:hash
set "FILE_HASH="
for /f "skip=1 delims=" %%H in ('certutil -hashfile "%~1" SHA256 2^>nul') do if not defined FILE_HASH set "FILE_HASH=%%H"
set "FILE_HASH=%FILE_HASH: =%"
if "%FILE_HASH:~63,1%"=="" exit /b 1
if not "%FILE_HASH:~64%"=="" exit /b 1
set "%~2=%FILE_HASH%"
exit /b 0
