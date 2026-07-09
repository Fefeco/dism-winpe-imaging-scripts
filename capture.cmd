@echo off
setlocal ENABLEDELAYEDEXPANSION

REM ============================================================
REM  CONFIGURATION
REM ============================================================
set "EXT_LABEL=IMAGENES"
set "EXT_DIR=WIM"

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

set "TS=%YYYY%%MM%%DD%_%HH%%MIN%"

REM ============================================================
REM  MODULE 1 — DETECT EXTERNAL DISK AND WINDOWS PARTITION
REM ============================================================
echo Buscando disco externo y particion de Windows...

set "DESTINO="
set "WINPART="

REM Scan all drive letters (excluding X: which is WinPE)
for %%X in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%X:\" (
        set "IS_BACKUP="
        for /f "tokens=5*" %%A in ('vol %%X: 2^>nul') do (
            if /I "%%A"=="%EXT_LABEL%" set "IS_BACKUP=1"
            if /I "%%B"=="%EXT_LABEL%" set "IS_BACKUP=1"
        )
        
        if defined IS_BACKUP (
            set "DESTINO=%%X:\%EXT_DIR%"
        ) else (
            if exist "%%X:\Windows\System32\config\SYSTEM" (
                if exist "%%X:\Users" (
                    set "WINPART=%%X:"
                )
            )
        )
    )
)

REM Validate backup destination
if not defined DESTINO (
    echo [ERROR] No se encontro ningun volumen con etiqueta "%EXT_LABEL%".
    echo Asegurate de que el disco externo esta conectado.
    pause
    exit /b 1
)

if not exist "%DESTINO%\" (
    echo [ERROR] El volumen tiene la etiqueta correcta pero NO existe la carpeta "%EXT_DIR%".
    echo Crea la carpeta "%EXT_DIR%" en el disco externo.
    pause
    exit /b 1
)

echo Disco externo detectado en: %DESTINO%

REM Create logs folder
if not exist "%DESTINO%\LOGS" mkdir "%DESTINO%\LOGS"
set "LOGFILE=%DESTINO%\LOGS\Backup_%TS%.log"

echo ===== INICIO DEL SCRIPT ===== > "%LOGFILE%"
echo Disco externo detectado en %DESTINO% >> "%LOGFILE%"

REM Validate Windows partition
if not defined WINPART (
    echo [ERROR] No se pudo detectar la particion de Windows.
    echo Esto puede significar que el disco esta cifrado con BitLocker.
    echo WinPE estandar NO puede desbloquear BitLocker.
    echo [ERROR] Windows no detectado. Posible BitLocker. >> "%LOGFILE%"
    pause
    exit /b 1
)

echo Particion de Windows detectada en: %WINPART%
echo Particion de Windows detectada en: %WINPART% >> "%LOGFILE%"

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

set "IMGNAME=%IMGBASE%_%TS%.wim"

echo Nombre final de imagen: %IMGNAME%
echo Nombre final de imagen: %IMGNAME% >> "%LOGFILE%"

REM ============================================================
REM  MODULE 3 — CAPTURE IMAGE WITH DISM
REM ============================================================
echo Iniciando captura...
echo Iniciando captura... >> "%LOGFILE%"

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

Dism /Capture-Image /ImageFile:"%DESTINO%\%IMGNAME%" /CaptureDir:%WINPART%\ /Name:"My Windows partition" /ConfigFile:"%TEMP%\exclude.ini" /CheckIntegrity
del "%TEMP%\exclude.ini"
set "ERR=%errorlevel%"

if not "%ERR%"=="0" (
    echo [ERROR] DISM devolvio codigo %ERR%.
    echo [ERROR] DISM devolvio codigo %ERR%. >> "%LOGFILE%"
    pause
    exit /b %ERR%
)

echo Captura completada correctamente.
echo Captura completada correctamente. >> "%LOGFILE%"

REM ============================================================
REM  END
REM ============================================================
echo Archivo generado: %DESTINO%\%IMGNAME%
echo Archivo generado: %DESTINO%\%IMGNAME% >> "%LOGFILE%"

echo ===== FIN DEL SCRIPT ===== >> "%LOGFILE%"

pause
exit /b 0
