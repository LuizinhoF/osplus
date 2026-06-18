$ErrorActionPreference = "Stop"

. "$PSScriptRoot\tools\_lib.ps1"

$SRC  = "$PSScriptRoot\mod\OSPlus\scripts"
$DATA_SRC = "$PSScriptRoot\data"
# UE4SS in this install is rooted directly at Binaries\Win64\Mods (not the older
# Binaries\Win64\ue4ss\Mods layout). If you migrate to a different UE4SS build
# that uses the nested layout again, update this path. The cooked .pak target
# is unrelated and lives under Content\Paks\LogicMods\OSPlus.pak.
$DEST = "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\Mods\OSPlus\Scripts"
$DATA_DEST = "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Binaries\Win64\Mods\OSPlus\data"

if (-not (Test-Path $DEST)) {
    Write-Fail "Game-side mod folder does not exist:"
    Write-Host "  $DEST" -ForegroundColor Red
    Write-Host ""
    Write-Warn2 "Did you rename the folder in your game install? See docs/UE_PROJECT_MIGRATION.md"
    exit 1
}

$SCRIPT_EXCLUDE_PATTERNS = @(
    "swap_test_*.lua",
    "probe_*.lua"
)
$files = Get-ChildItem "$SRC\*.lua" | Where-Object {
    $name = $_.Name
    -not ($SCRIPT_EXCLUDE_PATTERNS | Where-Object { $name -like $_ })
}
foreach ($f in $files) {
    Copy-Item $f.FullName "$DEST\$($f.Name)" -Force
}
$dataCopies = @(
    @{ Source = "$DATA_SRC\emotes\*.json"; Dest = "$DATA_DEST\emotes"; Label = "data\emotes" },
    @{ Source = "$DATA_SRC\localization\screens\*.json"; Dest = "$DATA_DEST\localization\screens"; Label = "data\localization\screens" }
)
foreach ($copy in $dataCopies) {
    New-Item -Path $copy.Dest -ItemType Directory -Force | Out-Null
    Copy-Item $copy.Source "$($copy.Dest)\" -Force
}
Write-Ok "Deployed $($files.Count) files to game directory."
foreach ($f in $files) { Write-Host "  $($f.Name)" }
Write-Ok "Deployed data files to game directory."
foreach ($copy in $dataCopies) {
    Get-ChildItem $copy.Source | ForEach-Object { Write-Host "  $($copy.Label)\$($_.Name)" }
}
