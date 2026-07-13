@echo off
REM ============================================================
REM  DISM WinPE Imaging Scripts
REM  Author: Fede (carranzafederico@gmail.com)
REM  GitHub: https://github.com/fefeco/dism-winpe-imaging-scripts
REM ============================================================
setlocal ENABLEDELAYEDEXPANSION

REM ============================================================
REM  CONFIGURATION
REM ============================================================
REM Drive letter of the storage drive (e.g., "D:").
REM Leave empty to automatically use the drive where this script is running (%~d0).
set "STORAGE_DRIVE="
set "WIM_DIR=WIM"
set "LOGS_DIR=Logs"

REM ============================================================
REM  RESOLVE STORAGE PATHS
REM ============================================================
set "STORAGE_PATH=%STORAGE_DRIVE%"
if "%STORAGE_PATH%"=="" (
    set "STORAGE_PATH=%~d0"
)

REM Verify if the storage drive is accessible
if not exist "%STORAGE_PATH%\" (
    echo [ERROR] No se puede acceder a la unidad de almacenamiento "%STORAGE_PATH%".
    echo Asegurate de que el disco externo esta conectado y tiene la letra correcta.
    pause
    exit /b 1
)

set "WIM_PATH=%STORAGE_PATH%\%WIM_DIR%"
set "LOGS_PATH=%STORAGE_PATH%\%LOGS_DIR%"

REM Create folders if they don't exist
if not exist "%WIM_PATH%" mkdir "%WIM_PATH%"
if not exist "%LOGS_PATH%" mkdir "%LOGS_PATH%"

REM ============================================================
REM  TIMESTAMP FOR LOG AND IMAGE NAME
REM ============================================================
for /f "tokens=1-4 delims=/.- " %%a in ("%date%") do (
    set "t1=%%a"
    set "t2=%%b"
    set "t3=%%c"
    set "t4=%%d"
)
if "%t1:~3,1%" neq "" (
    set "YYYY=%t1%"
    set "MM=%t2%"
    set "DD=%t3%"
)
if "%t3:~3,1%" neq "" (
    set "YYYY=%t3%"
    set "MM=%t2%"
    set "DD=%t1%"
)
if "%t4:~3,1%" neq "" (
    set "YYYY=%t4%"
    set "MM=%t2%"
    set "DD=%t3%"
)
for /f "tokens=1-2 delims=:." %%h in ("%time%") do (
    set "HH=%%h"
    set "MIN=%%i"
)
if "%HH:~0,1%"==" " set "HH=0%HH:~1,1%"

set "TIMESTAMP=%YYYY%%MM%%DD%_%HH%%MIN%"

set "LOG_FILE=%LOGS_PATH%\Backup_%TIMESTAMP%.log"

echo ===== INICIO DEL SCRIPT ===== > "%LOG_FILE%"
echo Disco de almacenamiento resuelto en: %STORAGE_PATH% >> "%LOG_FILE%"

REM ============================================================
REM  MODULE 1 — DETECT WINDOWS PARTITION
REM ============================================================
echo Buscando particion de Windows...

set "WINPART="

REM Scan all drive letters (excluding X: which is WinPE)
for %%X in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%X:\" (
        if exist "%%X:\Windows\System32\config\SYSTEM" (
            if exist "%%X:\Users" (
                set "WINPART=%%X:"
            )
        )
    )
)

REM Validate Windows partition
if not defined WINPART (
    echo [ERROR] No se pudo detectar la particion de Windows.
    echo Esto puede significar que el disco esta cifrado con BitLocker o desconectado.
    echo WinPE estandar NO puede desbloquear BitLocker.
    echo [ERROR] Windows no detectado. Posible BitLocker. >> "%LOG_FILE%"
    pause
    exit /b 1
)

echo Particion de Windows detectada en: %WINPART%
echo Particion de Windows detectada en: %WINPART% >> "%LOG_FILE%"

REM ============================================================
REM  MODULE 2 — REQUEST BASE NAME
REM ============================================================
echo.
set "IMGBASE="
echo Introduce el nombre base de la imagen (sin extension):
set /p IMGBASE=Nombre: 

if "%IMGBASE%"=="" (
    echo [ERROR] El nombre no puede estar vacio.
    pause
    exit /b 1
)

set "IMGNAME=%IMGBASE%_%TIMESTAMP%.wim"

echo Nombre final de imagen: %IMGNAME%
echo Nombre final de imagen: %IMGNAME% >> "%LOG_FILE%"

REM ============================================================
REM  MODULE 3 — CAPTURE IMAGE WITH DISM
REM ============================================================
echo Iniciando captura...
echo Iniciando captura... >> "%LOG_FILE%"

REM Note: Custom /ConfigFile overrides default DISM exclusions (e.g. pagefile.sys).
REM We must write the default system exclusions manually first.
(
echo [ExclusionList]
echo \$ntfs.log
echo \hiberfil.sys
echo \pagefile.sys
echo \swapfile.sys
echo \System Volume Information
echo \RECYCLER
echo \Windows\CSC
for /d %%U in ("%WINPART%\Users\*") do (
    set "UNAME=%%~nxU"
    if /I not "!UNAME!"=="All Users" (
        if /I not "!UNAME!"=="Default User" (
            for /d %%O in ("%%U\OneDrive*") do (
                echo \Users\!UNAME!\%%~nxO\*
            )
        )
    )
)
) > "%TEMP%\exclude.ini"

Dism /Capture-Image /ImageFile:"%WIM_PATH%\%IMGNAME%" /CaptureDir:%WINPART%\ /Name:"My Windows partition" /ConfigFile:"%TEMP%\exclude.ini" /CheckIntegrity
del "%TEMP%\exclude.ini"
set "ERR=%errorlevel%"

if not "%ERR%"=="0" (
    echo [ERROR] DISM devolvio codigo %ERR%.
    echo [ERROR] DISM devolvio codigo %ERR%. >> "%LOG_FILE%"
    pause
    exit /b %ERR%
)

echo Captura completada correctamente.
echo Captura completada correctamente. >> "%LOG_FILE%"

REM ============================================================
REM  END
REM ============================================================
echo Archivo generado: %WIM_PATH%\%IMGNAME%
echo Archivo generado: %WIM_PATH%\%IMGNAME% >> "%LOG_FILE%"

echo ===== FIN DEL SCRIPT ===== >> "%LOG_FILE%"

pause
exit /b 0
