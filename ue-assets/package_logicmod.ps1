$ErrorActionPreference = "Stop"

$UNREALPAK      = "F:\UE510\UnrealEngine-5.1.0-release\Engine\Binaries\Win64\UnrealPak.exe"
$COOKED_DIR     = "F:\Omegamod\OmegaStonkers 5.1\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OSPlus"
$COOKED_LEGACY  = "F:\Omegamod\OmegaStonkers 5.1\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OmegaStrikersMod"
$LOGICMODS_DIR  = "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Content\Paks\LogicMods"
$OUTPUT_PAK     = "$LOGICMODS_DIR\OSPlus.pak"
$RESPONSE_FILE  = "F:\Omegamod\OmegaStonkers 5.1\Saved\pak_logicmod_response.txt"

if (-not (Test-Path $UNREALPAK)) { Write-Error "UnrealPak not found: $UNREALPAK"; exit 1 }
if (-not (Test-Path $COOKED_DIR)) {
    if (Test-Path $COOKED_LEGACY) {
        Write-Error @"
Cooked content not found at the new path:
    $COOKED_DIR

But found legacy cooked content at:
    $COOKED_LEGACY

You probably need to do the UE Editor migration (rename Content/Mods/OmegaStrikersMod -> OSPlus,
then re-cook). See: docs/UE_PROJECT_MIGRATION.md
"@
        exit 1
    }
    Write-Error "Cooked content not found: $COOKED_DIR (cook the project first)"
    exit 1
}

Write-Host "=== Packaging LogicMod (ModActor + Chat Widget) ===" -ForegroundColor Cyan
Write-Host "Cooked dir : $COOKED_DIR"
Write-Host "Output pak : $OUTPUT_PAK"
Write-Host ""

$lines = @()
$files = Get-ChildItem -Path $COOKED_DIR -Recurse -File
foreach ($f in $files) {
    $relativePath = $f.FullName.Substring($COOKED_DIR.Length).TrimStart("\")
    $mountPath = "../../../OmegaStrikers/Content/Mods/OSPlus/$relativePath"
    $mountPath = $mountPath -replace "\\", "/"
    $lines += "`"$($f.FullName)`" `"$mountPath`""
}

if ($lines.Count -eq 0) { Write-Error "No files to package"; exit 1 }

Write-Host "Found $($lines.Count) files:" -ForegroundColor Green
foreach ($l in $lines) { Write-Host "  $l" }
Write-Host ""

$lines | Out-File -FilePath $RESPONSE_FILE -Encoding ascii

if (Test-Path $OUTPUT_PAK) {
    Remove-Item $OUTPUT_PAK -Force
    Write-Host "Removed old pak"
}

Write-Host "Running UnrealPak..." -ForegroundColor Yellow
& $UNREALPAK $OUTPUT_PAK "-Create=$RESPONSE_FILE"

if ($LASTEXITCODE -eq 0 -and (Test-Path $OUTPUT_PAK)) {
    $pakSize = (Get-Item $OUTPUT_PAK).Length
    Write-Host ""
    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    Write-Host "Pak: $OUTPUT_PAK ($pakSize bytes)"
    Write-Host "Assets mount at /Game/Mods/OSPlus/" -ForegroundColor Cyan
} else {
    Write-Error "UnrealPak failed (exit code: $LASTEXITCODE)"
    exit 1
}
