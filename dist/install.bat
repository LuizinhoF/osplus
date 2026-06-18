@echo off
setlocal enabledelayedexpansion

echo ======================================
echo            OSPlus - Installer
echo ======================================
echo.

:: ---------------------------------------------------------------------------
:: Self-elevate to admin
:: Writing to Program Files (x86) requires elevation. Without it, copy /y
:: silently redirects writes via UAC virtualization, and our Zone.Identifier
:: strip targets the wrong file -- the unblocked .exe never reaches the real
:: install location. Re-launch ourselves elevated if not already admin.
:: ---------------------------------------------------------------------------

net session >nul 2>&1
if errorlevel 1 (
    echo [!] Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: ---------------------------------------------------------------------------
:: Find game install path via Steam's libraryfolders.vdf
:: ---------------------------------------------------------------------------

set "STEAM_DEFAULT=C:\Program Files (x86)\Steam"
set "GAME_DIR_NAME=OmegaStrikers"
set "GAME_PATH="

:: Check default Steam location first
if exist "!STEAM_DEFAULT!\steamapps\common\!GAME_DIR_NAME!\OmegaStrikers.exe" (
    set "GAME_PATH=!STEAM_DEFAULT!\steamapps\common\!GAME_DIR_NAME!"
    goto :found
)

:: Parse libraryfolders.vdf for additional Steam library paths
set "VDF=!STEAM_DEFAULT!\steamapps\libraryfolders.vdf"
if not exist "!VDF!" (
    echo [^^!] Could not find Steam at !STEAM_DEFAULT!
    goto :manual
)

for /f "tokens=1,* delims=	 " %%a in ('findstr /c:"\"path\"" "!VDF!"') do (
    set "LIB_PATH=%%b"
    set "LIB_PATH=!LIB_PATH:"=!"
    set "LIB_PATH=!LIB_PATH:\\=\!"
    if exist "!LIB_PATH!\steamapps\common\!GAME_DIR_NAME!\OmegaStrikers.exe" (
        set "GAME_PATH=!LIB_PATH!\steamapps\common\!GAME_DIR_NAME!"
        goto :found
    )
)

:manual
echo [^^!] Could not auto-detect Omega Strikers install path.
echo     Please enter the full path to your OmegaStrikers folder.
echo     Example: F:\SteamLibrary\steamapps\common\OmegaStrikers
echo.
set /p "GAME_PATH=Game path: "
if not exist "!GAME_PATH!\OmegaStrikers.exe" (
    echo [ERROR] OmegaStrikers.exe not found at "!GAME_PATH!"
    echo         Make sure you entered the correct path.
    pause
    exit /b 1
)

:found
echo [OK] Found Omega Strikers at:
echo      !GAME_PATH!
echo.

:: ---------------------------------------------------------------------------
:: Paths
:: ---------------------------------------------------------------------------

set "BIN_DIR=!GAME_PATH!\OmegaStrikers\Binaries\Win64"
set "MODS_DIR=!BIN_DIR!\Mods"
set "MOD_DIR=!MODS_DIR!\OSPlus"
set "SCRIPTS_DIR=!MOD_DIR!\Scripts"
set "SIDECAR_DIR=!MOD_DIR!\sidecar"
set "DATA_DIR=!MOD_DIR!\data"
set "PAK_DIR=!GAME_PATH!\OmegaStrikers\Content\Paks\LogicMods"
set "THIS_DIR=%~dp0"
set "UE4SS_SRC=!THIS_DIR!ue4ss-files"

if not exist "!BIN_DIR!" (
    echo [ERROR] Game Binaries\Win64 folder not found at:
    echo         !BIN_DIR!
    echo         Verify your game files in Steam.
    pause
    exit /b 1
)

:: ---------------------------------------------------------------------------
:: Migrate from old "OmegaStrikersTest" install if present
:: We changed the mod folder name in v2; clean up the old dir so the user
:: doesn't end up running both.
:: ---------------------------------------------------------------------------

if exist "!MODS_DIR!\OmegaStrikersTest" (
    echo [migrate] Removing legacy OmegaStrikersTest folder...
    rmdir /s /q "!MODS_DIR!\OmegaStrikersTest" 2>nul
)
if exist "!PAK_DIR!\OmegaStrikersMod.pak" (
    echo [migrate] Removing legacy OmegaStrikersMod.pak...
    del /q "!PAK_DIR!\OmegaStrikersMod.pak" 2>nul
)
:: CustomPings_P.pak is leftover from this project's pre-OSPlus prototype phase.
:: Not a game file, not referenced by any live OSPlus code, just dead weight in
:: the player's install. See docs/re/architecture/content-layout.md for full RE.
:: Note: it lives in Paks\, not Paks\LogicMods\, because it was a native UE
:: patch pak rather than a BPModLoaderMod-loaded pak.
set "PAKS_ROOT=!GAME_PATH!\OmegaStrikers\Content\Paks"
if exist "!PAKS_ROOT!\CustomPings_P.pak" (
    echo [migrate] Removing legacy CustomPings_P.pak ^(orphan prototype mod^)...
    del /q "!PAKS_ROOT!\CustomPings_P.pak" 2>nul
)

:: ---------------------------------------------------------------------------
:: Deploy UE4SS (only if not already installed)
:: ---------------------------------------------------------------------------

if exist "!BIN_DIR!\UE4SS.dll" (
    echo [OK] UE4SS already installed in Win64, skipping UE4SS deploy
    echo.
) else (
    echo Installing UE4SS v3.0.1 ^(flat layout^)...
    if not exist "!UE4SS_SRC!\UE4SS.dll" (
        echo [ERROR] Bundled UE4SS files missing from installer!
        echo         Expected: !UE4SS_SRC!\UE4SS.dll
        echo         Re-extract the zip and try again.
        pause
        exit /b 1
    )

    copy /y "!UE4SS_SRC!\dwmapi.dll"          "!BIN_DIR!\" >nul
    copy /y "!UE4SS_SRC!\UE4SS.dll"           "!BIN_DIR!\" >nul
    copy /y "!UE4SS_SRC!\UE4SS-settings.ini"  "!BIN_DIR!\" >nul
    copy /y "!UE4SS_SRC!\UE4SS-LICENSE.txt"   "!BIN_DIR!\" >nul

    if not exist "!MODS_DIR!" mkdir "!MODS_DIR!"
    xcopy /y /q /e /i "!UE4SS_SRC!\Mods" "!MODS_DIR!" >nul

    :: Strip Mark-of-the-Web from extracted DLLs (Windows blocks unblocked DLLs silently)
    del "!BIN_DIR!\dwmapi.dll:Zone.Identifier"          2>nul
    del "!BIN_DIR!\UE4SS.dll:Zone.Identifier"           2>nul
    del "!BIN_DIR!\UE4SS-settings.ini:Zone.Identifier"  2>nul

    echo [OK] UE4SS deployed
    echo.
)

:: ---------------------------------------------------------------------------
:: Deploy mod files
:: ---------------------------------------------------------------------------

echo Installing mod files...
echo.

if exist "!SCRIPTS_DIR!" rmdir /s /q "!SCRIPTS_DIR!" 2>nul
if exist "!DATA_DIR!\emotes" rmdir /s /q "!DATA_DIR!\emotes" 2>nul
if exist "!DATA_DIR!\localization\screens" rmdir /s /q "!DATA_DIR!\localization\screens" 2>nul
if not exist "!SCRIPTS_DIR!" mkdir "!SCRIPTS_DIR!"
if not exist "!SIDECAR_DIR!" mkdir "!SIDECAR_DIR!"
if not exist "!DATA_DIR!\emotes" mkdir "!DATA_DIR!\emotes"
if not exist "!DATA_DIR!\localization\screens" mkdir "!DATA_DIR!\localization\screens"
if not exist "!PAK_DIR!" mkdir "!PAK_DIR!"

echo   [1/5] Copying Lua scripts...
xcopy /y /q "!THIS_DIR!mod\scripts\*.lua" "!SCRIPTS_DIR!\" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy Lua scripts
    pause
    exit /b 1
)

echo   [2/5] Copying emote metadata...
xcopy /y /q /e /i "!THIS_DIR!mod\data" "!DATA_DIR!" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy emote metadata
    pause
    exit /b 1
)

echo   [3/5] Copying sidecar...
:: Kill any running sidecar so the copy doesn't fail with "file in use"
taskkill /f /im OSPlus.exe          >nul 2>&1
taskkill /f /im OmegaStrikersChat.exe >nul 2>&1
copy /y "!THIS_DIR!mod\sidecar\OSPlus.exe" "!SIDECAR_DIR!\" >nul
if errorlevel 1 (
    echo [ERROR] Could not copy sidecar exe. Is the game running? Close it and re-run.
    pause
    exit /b 1
)
copy /y "!THIS_DIR!mod\sidecar\launch_hidden.vbs"     "!SIDECAR_DIR!\" >nul
del "!SIDECAR_DIR!\OSPlus.exe:Zone.Identifier"        2>nul
del "!SIDECAR_DIR!\launch_hidden.vbs:Zone.Identifier" 2>nul
if not exist "!SIDECAR_DIR!\config.json" (
    copy /y "!THIS_DIR!mod\sidecar\config.json" "!SIDECAR_DIR!\" >nul
)

echo   [4/5] Copying Blueprint pak...
copy /y "!THIS_DIR!mod\OSPlus.pak" "!PAK_DIR!\" >nul

echo   [5/5] Enabling mod in mods.txt...
set "MODS_TXT=!MODS_DIR!\mods.txt"
findstr /c:"OSPlus" "!MODS_TXT!" >nul 2>&1
if errorlevel 1 (
    if exist "!MODS_TXT!" (
        echo OSPlus : 1 >> "!MODS_TXT!"
    ) else (
        echo OSPlus : 1 > "!MODS_TXT!"
    )
    echo        Added to mods.txt
) else (
    echo        Already in mods.txt
)

:: Also strip the old "OmegaStrikersTest : 1" line if it's still present
:: (left over from the legacy installer).
if exist "!MODS_TXT!" (
    findstr /v /c:"OmegaStrikersTest" "!MODS_TXT!" > "!MODS_TXT!.tmp" 2>nul
    move /y "!MODS_TXT!.tmp" "!MODS_TXT!" >nul 2>&1
)

:: ---------------------------------------------------------------------------
:: Belt-and-suspenders MOTW strip
:: del :Zone.Identifier above handles the common case, but PowerShell's
:: Unblock-File is more reliable across edge cases (long paths, locked ADS,
:: etc). Sweep the whole install dir to catch anything we missed.
:: ---------------------------------------------------------------------------

echo.
echo Stripping Mark-of-the-Web from all installed files...
powershell -NoProfile -Command "Get-ChildItem -Path '!MOD_DIR!','!BIN_DIR!\UE4SS.dll','!BIN_DIR!\dwmapi.dll','!BIN_DIR!\UE4SS-settings.ini','!PAK_DIR!\OSPlus.pak' -ErrorAction SilentlyContinue -Recurse -Force | Unblock-File -ErrorAction SilentlyContinue" 2>nul
echo [OK] All files unblocked

echo.
echo ======================================
echo  Installation complete!
echo ======================================
echo.
echo  Just launch Omega Strikers normally.
echo  Chat activates automatically in-match.
echo  Press Enter to type, Escape to cancel.
echo.
echo  Config: !SIDECAR_DIR!\config.json
echo  Uninstall: run uninstall.bat from this package
echo.
pause
