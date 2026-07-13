@echo off
REM ============================================================
REM  DISM WinPE Imaging Scripts
REM  Author: Fede (carranzafederico@gmail.com)
REM  GitHub: https://github.com/fefeco/dism-winpe-imaging-scripts
REM ============================================================
setlocal enabledelayedexpansion

REM ============================================================
REM  CONFIGURATION
REM ============================================================
REM Drive letter of the storage drive (e.g., "D:").
REM Leave empty to automatically use the drive where this script is running (%~d0).
set "STORAGE_DRIVE="
set "WIM_DIR=WIM"
set "LOGS_DIR=Logs"

REM Target disk number to wipe and install Windows on
set "TARGET_DISK=0"

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

if not exist "%LOGS_PATH%" mkdir "%LOGS_PATH%"

REM ============================================================
REM  TIMESTAMP GENERATION
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

set "LOG_FILE=%LOGS_PATH%\deploy_%TIMESTAMP%.log"

echo ==== INICIO DEL DESPLIEGUE ==== >> "%LOG_FILE%"
echo Fecha: %DATE% Hora: %TIME% >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

REM ============================================================
REM  DYNAMIC WIM FILE DETECTION
REM ============================================================

set COUNT=0

for %%A in ("%WIM_PATH%\*.wim") do (
    set /a COUNT+=1
    set "WIM[!COUNT!]=%%~fA"
    set "NAME[!COUNT!]=%%~nA"
)

REM If no images found, abort
if %COUNT%==0 (
    echo ERROR: No se encontraron archivos .wim en %WIM_PATH%
    echo ERROR: No se encontraron archivos .wim en %WIM_PATH% >> "%LOG_FILE%"
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
echo Imagen seleccionada: %WIMNAME% >> "%LOG_FILE%"
echo.

REM Display drive list and warning
echo ============================================================
echo  DISCOS DETECTADOS EN EL SISTEMA:
echo ============================================================
for /f "delims=" %%L in ('^(echo list disk ^) ^| diskpart') do (
    set "LINE=%%L"
    for /f "tokens=*" %%T in ("!LINE!") do set "TRIMMED=%%T"
    if /I "!TRIMMED:~0,4!"=="Disk" echo !LINE!
    if /I "!TRIMMED:~0,5!"=="Disco" echo !LINE!
)
echo ============================================================
echo.

set "USER_DISK="
set /p "USER_DISK=Seleccione el disco de destino [por defecto: %TARGET_DISK%]: "
if not "%USER_DISK%"=="" set "TARGET_DISK=%USER_DISK%"

echo.
echo ============================================================
echo  ADVERTENCIA: Se borrara por completo el Disco %TARGET_DISK%.
echo  TODO LO QUE HAYA EN EL DISCO SE PERDERA PARA SIEMPRE.
echo ============================================================
set "CONFIRM="
set /p "CONFIRM=Estas seguro de que deseas continuar? (S/N): "
if /I not "!CONFIRM!"=="S" (
    echo Despliegue abortado por el usuario.
    echo Despliegue abortado por el usuario. >> "%LOG_FILE%"
    pause
    exit /b 0
)
echo.

REM ============================================================
REM  PREPARE DISK (DISKPART)
REM ============================================================

echo === Ejecutando DiskPart... === >> "%LOG_FILE%"

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

diskpart /s "%DP_TEMP%" >> "%LOG_FILE%" 2>&1
del "%DP_TEMP%"
if errorlevel 1 (
    echo ERROR: DiskPart fallo. Revisa el log.
    echo ERROR: DiskPart fallo. >> "%LOG_FILE%"
    exit /b 1
)

REM ============================================================
REM  APPLY WIM IMAGE
REM ============================================================

echo === Aplicando imagen: %WIMNAME% === >> "%LOG_FILE%"

dism /apply-image /imagefile:"%WIMFILE%" /index:1 /ApplyDir:Z:\ /LogPath:"%LOG_FILE%" /CheckIntegrity
if errorlevel 1 (
    echo ERROR: DISM fallo al aplicar la imagen.
    echo ERROR: DISM fallo. >> "%LOG_FILE%"
    exit /b 1
)

REM ============================================================
REM  CREATE UEFI BOOTLOADER
REM ============================================================

echo === Configurando arranque UEFI === >> "%LOG_FILE%"

bcdboot Z:\Windows /s S: /f UEFI >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo ERROR: BCDBoot fallo.
    echo ERROR: BCDBoot fallo. >> "%LOG_FILE%"
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
echo %LOG_FILE%
echo.

echo ==== FIN DEL DESPLIEGUE ==== >> "%LOG_FILE%"

pause
exit /b 0
