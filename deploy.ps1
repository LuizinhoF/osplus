$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools\_lib.ps1"

$SRC  = "$PSScriptRoot\mod\OSPlus\scripts"
$DEST = "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\ue4ss\Mods\OSPlus\Scripts"

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
