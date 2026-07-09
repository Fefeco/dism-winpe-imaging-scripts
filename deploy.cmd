@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  INITIAL CONFIGURATION
REM ============================================================

REM WIM images directory (root of the USB drive)
set "IMGDIR=%~d0\WIM"

REM Logs directory
set "LOGDIR=%~d0\Logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

REM Target disk number to wipe and install Windows on
set "TARGET_DISK=0"

REM Extract locale-independent timestamp
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

set "LOG=%LOGDIR%\deploy_%TS%.log"

echo ==== INICIO DEL DESPLIEGUE ==== >> "%LOG%"
echo Fecha: %DATE% Hora: %TIME% >> "%LOG%"
echo. >> "%LOG%"

REM ============================================================
REM  DYNAMIC WIM FILE DETECTION
REM ============================================================

set COUNT=0

for %%A in ("%IMGDIR%\*.wim") do (
    set /a COUNT+=1
    set "WIM[!COUNT!]=%%~fA"
    set "NAME[!COUNT!]=%%~nA"
)

REM If no images found, abort
if %COUNT%==0 (
    echo ERROR: No se encontraron archivos .wim en %IMGDIR%
    echo ERROR: No se encontraron archivos .wim en %IMGDIR% >> "%LOG%"
    pause
    exit /b 1
)

REM ============================================================
REM  DYNAMIC MENU
REM ============================================================

:MENU
cls
echo ============================================
echo        MENU DE IMAGENES PARA DESPLIEGUE
echo ============================================
echo.

for /L %%i in (1,1,%COUNT%) do (
    echo %%i^) !NAME[%%i]!
)

set /a EXITOPT=%COUNT%+1
echo %EXITOPT%^) Salir
echo.

set /p "SEL=Selecciona una opcion [1-%EXITOPT%]: "

REM Validate input
if "%SEL%"=="" goto MENU
if %SEL% GTR %EXITOPT% goto MENU
if %SEL% LSS 1 goto MENU

REM Exit
if %SEL%==%EXITOPT% exit /b 0

REM Selected image
set "WIMFILE=!WIM[%SEL%]!"
set "WIMNAME=!NAME[%SEL%]!"

echo Imagen seleccionada: %WIMNAME%
echo Imagen seleccionada: %WIMNAME% >> "%LOG%"
echo.

REM Display warning and require explicit confirmation
echo ============================================================
echo  ADVERTENCIA: Se borrara el Disco %TARGET_DISK%. TODO SE PERDERA
echo ============================================================
set "CONFIRM="
set /p "CONFIRM=Estas seguro de que deseas continuar? (S/N): "
if /I not "!CONFIRM!"=="S" (
    echo Despliegue abortado por el usuario.
    echo Despliegue abortado por el usuario. >> "%LOG%"
    pause
    exit /b 0
)
echo.

REM ============================================================
REM  PREPARE DISK (DISKPART)
REM ============================================================

echo === Ejecutando DiskPart... === >> "%LOG%"

set "DP_TEMP=%temp%\dp_script.txt"

(
  echo select disk %TARGET_DISK%
  echo clean
  echo convert gpt
  echo create partition efi size=200
  echo format quick fs=fat32 label="EFI"
  echo assign letter=S
  echo create partition msr size=16
  echo create partition primary
  echo format quick fs=ntfs label="Windows"
  echo assign letter=Z
  echo exit
) > "%DP_TEMP%"

diskpart /s "%DP_TEMP%" >> "%LOG%" 2>&1
del "%DP_TEMP%"
if errorlevel 1 (
    echo ERROR: DiskPart fallo. Revisa el log.
    echo ERROR: DiskPart fallo. >> "%LOG%"
    exit /b 1
)

REM ============================================================
REM  APPLY WIM IMAGE
REM ============================================================

echo === Aplicando imagen: %WIMNAME% === >> "%LOG%"

dism /apply-image /imagefile:"%WIMFILE%" /index:1 /ApplyDir:Z:\ /LogPath:"%LOG%" /CheckIntegrity
if errorlevel 1 (
    echo ERROR: DISM fallo al aplicar la imagen.
    echo ERROR: DISM fallo. >> "%LOG%"
    exit /b 1
)

REM ============================================================
REM  CREATE UEFI BOOTLOADER
REM ============================================================

echo === Configurando arranque UEFI === >> "%LOG%"

bcdboot Z:\Windows /s S: /f UEFI >> "%LOG%" 2>&1
if errorlevel 1 (
    echo ERROR: BCDBoot fallo.
    echo ERROR: BCDBoot fallo. >> "%LOG%"
    exit /b 1
)

REM ============================================================
REM  FINALIZE
REM ============================================================

echo.
echo ============================================
echo      DESPLIEGUE COMPLETADO CON EXITO
echo ============================================
echo.
echo Log guardado en:
echo %LOG%
echo.

echo ==== FIN DEL DESPLIEGUE ==== >> "%LOG%"

pause
exit /b 0
