$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools\_lib.ps1"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Building OSPlus Distribution Package  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$ROOT        = $PSScriptRoot
$DIST        = "$ROOT\dist\OSPlus"
$SIDECAR_SRC = "$ROOT\sidecar"
$SCRIPTS_SRC = "$ROOT\mod\OSPlus\scripts"
$DATA_SRC    = "$ROOT\data"
$UE4SS_SRC   = "$ROOT\ue4ss-bundle"
$ZIP_OUT     = "$ROOT\dist\OSPlus.zip"

# Final dist requires the new OSPlus.pak. The legacy OmegaStrikersMod.pak
# is detected only so we can give a clear error if someone forgot to re-cook
# after the UE editor folder rename (see docs/UE_PROJECT_MIGRATION.md).
$PAK_NEW     = "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Content\Paks\LogicMods\OSPlus.pak"
$PAK_LEGACY  = "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Content\Paks\LogicMods\OmegaStrikersMod.pak"
$PAK_SRC     = $PAK_NEW

# ---------------------------------------------------------------------------
# 1. Clean dist folder
# ---------------------------------------------------------------------------

Write-Step "[1/7] Cleaning dist folder"
try {
    if (Test-Path $DIST) { Remove-Item $DIST -Recurse -Force -ErrorAction Stop }
    Write-Ok "Dist folder cleaned"
} catch {
    Write-Warn2 "Could not fully clean, overwriting in place"
}
New-Item -Path "$DIST\mod\scripts"  -ItemType Directory -Force | Out-Null
New-Item -Path "$DIST\mod\sidecar"  -ItemType Directory -Force | Out-Null
New-Item -Path "$DIST\mod\data\emotes" -ItemType Directory -Force | Out-Null
New-Item -Path "$DIST\mod\data\localization\screens" -ItemType Directory -Force | Out-Null

# ---------------------------------------------------------------------------
# 2. Copy Lua scripts
# ---------------------------------------------------------------------------

Write-Step "[2/7] Copying Lua scripts"
$SCRIPT_EXCLUDE_PATTERNS = @(
    "swap_test_*.lua",
    "probe_*.lua"
)
Get-ChildItem "$SCRIPTS_SRC\*.lua" -File |
    Where-Object {
        $name = $_.Name
        -not ($SCRIPT_EXCLUDE_PATTERNS | Where-Object { $name -like $_ })
    } |
    Copy-Item -Destination "$DIST\mod\scripts\" -Force
$luaCount = (Get-ChildItem "$DIST\mod\scripts\*.lua").Count
Write-Ok "Copied $luaCount Lua scripts"

Copy-Item "$DATA_SRC\emotes\*.json" "$DIST\mod\data\emotes\" -Force
Copy-Item "$DATA_SRC\localization\screens\*.json" "$DIST\mod\data\localization\screens\" -Force
$dataCount = (Get-ChildItem "$DIST\mod\data\*.json" -Recurse).Count
Write-Ok "Copied $dataCount data file(s)"

# ---------------------------------------------------------------------------
# 3. Build sidecar exe
# ---------------------------------------------------------------------------

Write-Step "[3/7] Building sidecar exe"

Push-Location $SIDECAR_SRC
# npm/esbuild/postject emit informational lines on stderr that PS treats as
# errors when $ErrorActionPreference = Stop. Switch to Continue around the
# tool calls; restore on the way out via finally.
$prevPref = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    & npm install --silent 2>&1 | Where-Object { $_ -notmatch "^npm warn" }

    & npx esbuild index.js --bundle --platform=node --outfile=bundle.js 2>&1 | Where-Object { $_ -notmatch "^$" }
    if (-not (Test-Path "bundle.js")) { throw "esbuild failed" }

    & node --experimental-sea-config sea-config.json 2>&1 | Write-Host
    if (-not (Test-Path "sea-prep.blob")) { throw "SEA config failed" }

    $nodeExe = (Get-Command node).Source
    Copy-Item $nodeExe "OSPlus.exe" -Force

    & npx postject OSPlus.exe NODE_SEA_BLOB sea-prep.blob --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2 --overwrite 2>&1 | Write-Host
    if (-not (Test-Path "OSPlus.exe")) { throw "postject failed" }

    Write-Ok "Sidecar exe built"
} finally {
    $ErrorActionPreference = $prevPref
    Pop-Location
}

Copy-Item "$SIDECAR_SRC\OSPlus.exe"          "$DIST\mod\sidecar\" -Force
Copy-Item "$SIDECAR_SRC\launch_hidden.vbs"   "$DIST\mod\sidecar\" -Force

# Default config — points at the production OSPlus relay. Users who want
# to run their own relay can edit this post-install (or before, by editing
# this script and rebuilding).
$configJson = @{ relay_url = "wss://play-osplus.duckdns.org" } | ConvertTo-Json
[System.IO.File]::WriteAllText("$DIST\mod\sidecar\config.json", $configJson)

Write-Ok "Copied exe + launcher + config.json"

# ---------------------------------------------------------------------------
# 4. Copy pak file (rename to OSPlus.pak in dist regardless of source name)
# ---------------------------------------------------------------------------

Write-Step "[4/7] Copying pak"
if (Test-Path $PAK_SRC) {
    Copy-Item $PAK_SRC "$DIST\mod\OSPlus.pak" -Force
    Write-Ok "Copied OSPlus.pak"
} else {
    Write-Fail "OSPlus.pak not found at:"
    Write-Host "         $PAK_NEW" -ForegroundColor Red
    if (Test-Path $PAK_LEGACY) {
        Write-Host ""                                                                              -ForegroundColor Yellow
        Write-Host "       Found legacy OmegaStrikersMod.pak instead. You renamed the BP folder"   -ForegroundColor Yellow
        Write-Host "       in the UE Editor but haven't re-cooked + re-packaged yet."              -ForegroundColor Yellow
        Write-Host ""                                                                              -ForegroundColor Yellow
        Write-Host "       Fix:"                                                                   -ForegroundColor Yellow
        Write-Host "         1. UE Editor: File -> Cook Content for Windows"                       -ForegroundColor Yellow
        Write-Host "         2. .\ue-assets\package_logicmod.ps1"                                  -ForegroundColor Yellow
        Write-Host "         3. .\build_dist.ps1   (this script)"                                  -ForegroundColor Yellow
    } else {
        Write-Host "       Cook the UE project and run .\ue-assets\package_logicmod.ps1 first."    -ForegroundColor Yellow
    }
    throw "Missing OSPlus.pak -- refusing to build a broken dist."
}

# ---------------------------------------------------------------------------
# 5. Copy bundled UE4SS (flat layout — DLLs + Mods folder)
# ---------------------------------------------------------------------------

Write-Step "[5/7] Copying UE4SS bundle"
if (Test-Path $UE4SS_SRC) {
    Copy-Item "$UE4SS_SRC" "$DIST\ue4ss-files" -Recurse -Force
    $ue4ssSize = [math]::Round((Get-ChildItem "$DIST\ue4ss-files" -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 2)
    Write-Ok "Copied UE4SS bundle ($ue4ssSize MB)"
} else {
    Write-Fail "UE4SS bundle not found at $UE4SS_SRC"
    throw "Missing ue4ss-bundle/ — run setup first"
}

# ---------------------------------------------------------------------------
# 6. Copy installers + README.txt
# ---------------------------------------------------------------------------

Write-Step "[6/7] Copying installers + README"
Copy-Item "$ROOT\dist\install.bat" "$DIST\" -Force
Copy-Item "$ROOT\dist\install.sh"  "$DIST\" -Force
Copy-Item "$ROOT\dist\uninstall.bat" "$DIST\" -Force
Copy-Item "$ROOT\dist\uninstall.sh"  "$DIST\" -Force
Copy-Item "$ROOT\dist\README.txt"  "$DIST\" -Force
Write-Ok "Copied installers + README.txt"

# ---------------------------------------------------------------------------
# 7. Zip everything
# ---------------------------------------------------------------------------

Write-Step "[7/7] Zipping dist"
if (Test-Path $ZIP_OUT) { Remove-Item $ZIP_OUT -Force }
Compress-Archive -Path "$DIST\*" -DestinationPath $ZIP_OUT -CompressionLevel Optimal
$zipSize = [math]::Round((Get-Item $ZIP_OUT).Length / 1MB, 2)
Write-Ok "Created $ZIP_OUT ($zipSize MB)"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Build complete!" -ForegroundColor Green
Write-Host " Zip: $ZIP_OUT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "Contents:" -ForegroundColor White
Get-ChildItem $DIST -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($DIST.Length + 1)
    $size = [math]::Round($_.Length / 1KB, 1)
    Write-Host "  $rel ($size KB)"
}
