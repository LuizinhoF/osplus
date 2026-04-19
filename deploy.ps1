$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools\_lib.ps1"

$SRC  = "$PSScriptRoot\mod\OSPlus\scripts"
# UE4SS in this install is rooted directly at Binaries\Win64\Mods (not the older
# Binaries\Win64\ue4ss\Mods layout). If you migrate to a different UE4SS build
# that uses the nested layout again, update this path. The cooked .pak target
# is unrelated and lives under Content\Paks\LogicMods\OSPlus.pak.
$DEST = "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\Mods\OSPlus\Scripts"

if (-not (Test-Path $DEST)) {
    Write-Fail "Game-side mod folder does not exist:"
    Write-Host "  $DEST" -ForegroundColor Red
    Write-Host ""
    Write-Warn2 "Did you rename the folder in your game install? See docs/UE_PROJECT_MIGRATION.md"
    exit 1
}

$files = Get-ChildItem "$SRC\*.lua"
foreach ($f in $files) {
    Copy-Item $f.FullName "$DEST\$($f.Name)" -Force
}
Write-Ok "Deployed $($files.Count) files to game directory."
foreach ($f in $files) { Write-Host "  $($f.Name)" }
