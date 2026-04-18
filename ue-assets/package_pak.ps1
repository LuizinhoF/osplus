# package_pak.ps1 — Package cooked UE assets into a .pak for Omega Strikers
#
# Usage: .\package_pak.ps1

$ErrorActionPreference = "Stop"

$UNREALPAK      = "F:\UE_5.1\Engine\Binaries\Win64\UnrealPak.exe"
$COOKED_CONTENT = "F:\Omegamod\OmegaStonkers\Saved\Cooked\Windows\OmegaStonkers\Content"
$COOKED_DIR     = "$COOKED_CONTENT\CustomPings"
$GAME_PAKS_DIR  = "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Content\Paks"
$OUTPUT_PAK     = "$GAME_PAKS_DIR\CustomPings_P.pak"
$RESPONSE_FILE  = "F:\Omegamod\OmegaStonkers\Saved\pak_response.txt"

# Skip files we don't need in the mod pak (keep project shader archives!)
$SKIP_PATTERNS  = @("HLOD", "ShaderArchive-Global", "ShaderAssetInfo-Global")

if (-not (Test-Path $UNREALPAK)) { Write-Error "UnrealPak not found: $UNREALPAK"; exit 1 }
if (-not (Test-Path $COOKED_DIR)) { Write-Error "Cooked content not found: $COOKED_DIR"; exit 1 }

Write-Host "=== Packaging Custom Ping Assets ===" -ForegroundColor Cyan
Write-Host "Cooked dir : $COOKED_DIR"
Write-Host "Output pak : $OUTPUT_PAK"
Write-Host ""

$lines = @()

# Include custom ping assets
$files = Get-ChildItem -Path $COOKED_DIR -Recurse -File
foreach ($f in $files) {
    $skip = $false
    foreach ($pat in $SKIP_PATTERNS) {
        if ($f.Name -match $pat) { $skip = $true; break }
    }
    if ($skip) { continue }

    $relativePath = $f.FullName.Substring($COOKED_DIR.Length).TrimStart("\")
    $mountPath = "../../../OmegaStrikers/Content/CustomPings/$relativePath"
    $mountPath = $mountPath -replace "\\", "/"
    $lines += "`"$($f.FullName)`" `"$mountPath`""
}

# Include project shader archives (required for custom material shaders)
$shaderFiles = Get-ChildItem -Path $COOKED_CONTENT -File | Where-Object {
    ($_.Name -match "ShaderArchive-OmegaStonkers" -or $_.Name -match "ShaderAssetInfo-OmegaStonkers")
}
foreach ($f in $shaderFiles) {
    $mountPath = "../../../OmegaStrikers/Content/$($f.Name)"
    $lines += "`"$($f.FullName)`" `"$mountPath`""
    Write-Host "  [SHADER] $($f.Name) ($($f.Length) bytes)" -ForegroundColor Magenta
}

if ($lines.Count -eq 0) { Write-Error "No files to package"; exit 1 }

Write-Host "Found $($lines.Count) files to package:" -ForegroundColor Green
foreach ($l in $lines) { Write-Host "  $l" }
Write-Host ""

$lines | Out-File -FilePath $RESPONSE_FILE -Encoding ascii
Write-Host "Response file: $RESPONSE_FILE"

if (Test-Path $OUTPUT_PAK) {
    Remove-Item $OUTPUT_PAK -Force
    Write-Host "Removed old pak"
}

Write-Host ""
Write-Host "Running UnrealPak..." -ForegroundColor Yellow
$createArg = "-Create=$RESPONSE_FILE"
& $UNREALPAK $OUTPUT_PAK $createArg

if ($LASTEXITCODE -eq 0 -and (Test-Path $OUTPUT_PAK)) {
    $pakSize = (Get-Item $OUTPUT_PAK).Length
    Write-Host ""
    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    Write-Host "Pak: $OUTPUT_PAK ($pakSize bytes)"
    Write-Host "Assets mount at /Game/CustomPings/Textures/" -ForegroundColor Cyan
} else {
    Write-Error "UnrealPak failed (exit code: $LASTEXITCODE)"
    exit 1
}
