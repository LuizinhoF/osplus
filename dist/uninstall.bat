@echo off
setlocal enabledelayedexpansion

echo ======================================
echo           OSPlus - Uninstaller
echo ======================================
echo.

:: Writing to Program Files (x86) may require elevation. Re-launch elevated if
:: needed so deletes do not silently fail.
net session >nul 2>&1
if errorlevel 1 (
    echo [!] Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "STEAM_DEFAULT=C:\Program Files (x86)\Steam"
set "GAME_DIR_NAME=OmegaStrikers"
set "GAME_PATH="

if exist "!STEAM_DEFAULT!\steamapps\common\!GAME_DIR_NAME!\OmegaStrikers.exe" (
    set "GAME_PATH=!STEAM_DEFAULT!\steamapps\common\!GAME_DIR_NAME!"
    goto :found
)

set "VDF=!STEAM_DEFAULT!\steamapps\libraryfolders.vdf"
if exist "!VDF!" (
    for /f "tokens=1,* delims=	 " %%a in ('findstr /c:"\"path\"" "!VDF!"') do (
        set "LIB_PATH=%%b"
        set "LIB_PATH=!LIB_PATH:"=!"
        set "LIB_PATH=!LIB_PATH:\\=\!"
        if exist "!LIB_PATH!\steamapps\common\!GAME_DIR_NAME!\OmegaStrikers.exe" (
            set "GAME_PATH=!LIB_PATH!\steamapps\common\!GAME_DIR_NAME!"
            goto :found
        )
    )
)

echo [^^!] Could not auto-detect Omega Strikers install path.
echo     Please enter the full path to your OmegaStrikers folder.
echo     Example: F:\SteamLibrary\steamapps\common\OmegaStrikers
echo.
set /p "GAME_PATH=Game path: "
if not exist "!GAME_PATH!\OmegaStrikers.exe" (
    echo [ERROR] OmegaStrikers.exe not found at "!GAME_PATH!"
    pause
    exit /b 1
)

:found
echo [OK] Found Omega Strikers at:
echo      !GAME_PATH!
echo.

set "BIN_DIR=!GAME_PATH!\OmegaStrikers\Binaries\Win64"
set "MODS_DIR=!BIN_DIR!\Mods"
set "MOD_DIR=!MODS_DIR!\OSPlus"
set "PAKS_ROOT=!GAME_PATH!\OmegaStrikers\Content\Paks"
set "PAK_DIR=!PAKS_ROOT!\LogicMods"
set "MODS_TXT=!MODS_DIR!\mods.txt"

echo Stopping OSPlus sidecar if it is running...
taskkill /f /im OSPlus.exe            >nul 2>&1
taskkill /f /im OmegaStrikersChat.exe >nul 2>&1

echo Removing OSPlus mod files...
if exist "!MOD_DIR!" rmdir /s /q "!MOD_DIR!" 2>nul
if exist "!PAK_DIR!\OSPlus.pak" del /q "!PAK_DIR!\OSPlus.pak" 2>nul
if exist "!PAK_DIR!\OmegaStrikersMod.pak" del /q "!PAK_DIR!\OmegaStrikersMod.pak" 2>nul
if exist "!PAKS_ROOT!\CustomPings_P.pak" del /q "!PAKS_ROOT!\CustomPings_P.pak" 2>nul

if exist "!MODS_TXT!" (
    findstr /v /r /c:"^[ ]*OSPlus[ ]*:" /c:"^[ ]*OmegaStrikersTest[ ]*:" "!MODS_TXT!" > "!MODS_TXT!.tmp" 2>nul
    move /y "!MODS_TXT!.tmp" "!MODS_TXT!" >nul 2>&1
)

echo.
choice /m "Remove UE4SS too? Choose No if any other UE4SS mod uses this install"
if errorlevel 2 goto :skip_ue4ss
if exist "!BIN_DIR!\dwmapi.dll" del /q "!BIN_DIR!\dwmapi.dll" 2>nul
if exist "!BIN_DIR!\UE4SS.dll" del /q "!BIN_DIR!\UE4SS.dll" 2>nul
if exist "!BIN_DIR!\UE4SS-settings.ini" del /q "!BIN_DIR!\UE4SS-settings.ini" 2>nul
if exist "!BIN_DIR!\UE4SS-LICENSE.txt" del /q "!BIN_DIR!\UE4SS-LICENSE.txt" 2>nul
if exist "!MODS_DIR!\BPModLoaderMod" rmdir /s /q "!MODS_DIR!\BPModLoaderMod" 2>nul
if exist "!MODS_DIR!\shared" rmdir /s /q "!MODS_DIR!\shared" 2>nul
echo [OK] UE4SS files removed
goto :ask_data

:skip_ue4ss
echo [OK] UE4SS left installed

:ask_data
echo.
choice /m "Remove local OSPlus logs/config/token too? Reinstalling will create a new token"
if errorlevel 2 goto :skip_data
if exist "%LOCALAPPDATA%\OSPlus" rmdir /s /q "%LOCALAPPDATA%\OSPlus" 2>nul
echo [OK] Local OSPlus data removed
goto :done

:skip_data
echo [OK] Local OSPlus data left in place

:done
echo.
echo ======================================
echo  Uninstall complete!
echo ======================================
echo.
pause
