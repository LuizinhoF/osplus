$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Building OSPlus Distribution Package  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$ROOT        = $PSScriptRoot
$DIST        = "$ROOT\dist\OSPlus"
$SIDECAR_SRC = "$ROOT\sidecar"
$SCRIPTS_SRC = "$ROOT\mod\OSPlus\scripts"
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

try {
    if (Test-Path $DIST) { Remove-Item $DIST -Recurse -Force -ErrorAction Stop }
    Write-Host "[1/7] Cleaned dist folder" -ForegroundColor Green
} catch {
    Write-Host "[1/7] Could not fully clean dist folder, overwriting in place" -ForegroundColor Yellow
}
New-Item -Path "$DIST\mod\scripts"  -ItemType Directory -Force | Out-Null
New-Item -Path "$DIST\mod\sidecar"  -ItemType Directory -Force | Out-Null

# ---------------------------------------------------------------------------
# 2. Copy Lua scripts
# ---------------------------------------------------------------------------

Copy-Item "$SCRIPTS_SRC\*.lua" "$DIST\mod\scripts\" -Force
$luaCount = (Get-ChildItem "$DIST\mod\scripts\*.lua").Count
Write-Host "[2/7] Copied $luaCount Lua scripts" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. Build sidecar exe
# ---------------------------------------------------------------------------

Write-Host "[3/7] Building sidecar exe..." -ForegroundColor Yellow

Push-Location $SIDECAR_SRC
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

    Write-Host "       Sidecar exe built successfully" -ForegroundColor Green
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

Write-Host "       Copied exe + launcher + config.json" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 4. Copy pak file (rename to OSPlus.pak in dist regardless of source name)
# ---------------------------------------------------------------------------

if (Test-Path $PAK_SRC) {
    Copy-Item $PAK_SRC "$DIST\mod\OSPlus.pak" -Force
    Write-Host "[4/7] Copied pak (OSPlus.pak)" -ForegroundColor Green
} else {
    Write-Host "[4/7] ERROR: OSPlus.pak not found at:" -ForegroundColor Red
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

if (Test-Path $UE4SS_SRC) {
    Copy-Item "$UE4SS_SRC" "$DIST\ue4ss-files" -Recurse -Force
    $ue4ssSize = [math]::Round((Get-ChildItem "$DIST\ue4ss-files" -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 2)
    Write-Host "[5/7] Copied UE4SS bundle ($ue4ssSize MB)" -ForegroundColor Green
} else {
    Write-Host "[5/7] ERROR: UE4SS bundle not found at $UE4SS_SRC" -ForegroundColor Red
    throw "Missing ue4ss-bundle/ — run setup first"
}

# ---------------------------------------------------------------------------
# 6. Copy install.bat + README.txt
# ---------------------------------------------------------------------------

Copy-Item "$ROOT\dist\install.bat" "$DIST\" -Force
Copy-Item "$ROOT\dist\README.txt"  "$DIST\" -Force
Write-Host "[6/7] Copied install.bat + README.txt" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 7. Zip everything
# ---------------------------------------------------------------------------

if (Test-Path $ZIP_OUT) { Remove-Item $ZIP_OUT -Force }
Compress-Archive -Path "$DIST\*" -DestinationPath $ZIP_OUT -CompressionLevel Optimal
$zipSize = [math]::Round((Get-Item $ZIP_OUT).Length / 1MB, 2)
Write-Host "[7/7] Created $ZIP_OUT ($zipSize MB)" -ForegroundColor Green

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
