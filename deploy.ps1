$SRC  = "$PSScriptRoot\mod\OSPlus\scripts"
$DEST = "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\ue4ss\Mods\OSPlus\Scripts"

if (-not (Test-Path $DEST)) {
    Write-Host "ERROR: Game-side mod folder does not exist:" -ForegroundColor Red
    Write-Host "  $DEST" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "Did you rename the folder in your game install? See docs/UE_PROJECT_MIGRATION.md" -ForegroundColor Yellow
    exit 1
}

$files = Get-ChildItem "$SRC\*.lua"
foreach ($f in $files) {
    Copy-Item $f.FullName "$DEST\$($f.Name)" -Force
}
Write-Host "Deployed $($files.Count) files to game directory." -ForegroundColor Green
foreach ($f in $files) { Write-Host "  $($f.Name)" }
