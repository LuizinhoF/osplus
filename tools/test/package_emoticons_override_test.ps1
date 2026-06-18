# THROWAWAY — Stage-3 Pass-2 A1 closing experiment.
#
# Packs a single overridden asset (WBP_Panel_StrikerEmoticons cooked at the
# native path /Game/Prometheus/UI/OutOfGame/Strikers/) into a separate pak
# that loads alongside OSPlus.pak in LogicMods/.
#
# Goal: prove pak-mount priority lets OSPlus override base-game assets at
# the native path. Once the verdict is recorded in the feature Brief and a
# learning entry, DELETE this script — production override packing will
# fold into ue-assets/package_logicmod.ps1.
#
# See: docs/features/emote-loadout-ui-improvement.md (Feasibility A1)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\_lib.ps1"

$UNREALPAK     = "F:\UE510\UnrealEngine-5.1.0-release\Engine\Binaries\Win64\UnrealPak.exe"
$COOKED_BASE   = "F:\Omegamod\OmegaStonkers 5.1\Saved\Cooked\Windows\OmegaStonkers\Content"
$OVERRIDE_REL  = "Prometheus\UI\OutOfGame\Strikers"
$OVERRIDE_DIR  = Join-Path $COOKED_BASE $OVERRIDE_REL
$LOGICMODS_DIR = "F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Content\Paks\LogicMods"
# `_P` suffix puts the pak in UE5's "patch" priority bucket (priority +100),
# which is required to win path-collision lookups against base-game assets.
# Without `_P` the pak mounts at default priority and the base pak wins.
$OUTPUT_PAK    = "$LOGICMODS_DIR\~OSPlus_EmoticonsTest_P.pak"
# Clean up any prior non-_P version from earlier iterations
$STALE_PAK     = "$LOGICMODS_DIR\~OSPlus_EmoticonsTest.pak"
if (Test-Path $STALE_PAK) {
    Remove-Item $STALE_PAK -Force
    Write-Host "    Removed stale (non-_P) pak: $STALE_PAK" -ForegroundColor DarkGray
}
$RESPONSE_FILE = "F:\Omegamod\OmegaStonkers 5.1\Saved\pak_emoticons_override_test_response.txt"

if (-not (Test-Path $UNREALPAK)) {
    Write-Fail "UnrealPak not found: $UNREALPAK"
    exit 1
}
if (-not (Test-Path $OVERRIDE_DIR)) {
    Write-Fail "Cooked override dir not found: $OVERRIDE_DIR"
    Write-Host @"

You probably haven't cooked yet, or /Game/Prometheus/UI/OutOfGame/Strikers
is not in Project Settings -> Packaging -> Additional Asset Directories to
Cook. Add it (alongside /Game/Mods/OSPlus), then File -> Cook Content for
Windows.
"@ -ForegroundColor Yellow
    exit 1
}

Write-Step "Packaging Emoticons override (smoke test)"
Write-Host "    Cooked dir : $OVERRIDE_DIR"
Write-Host "    Output pak : $OUTPUT_PAK"

$lines = @()
$files = Get-ChildItem -Path $OVERRIDE_DIR -Recurse -File |
    Where-Object { $_.Name -match '\.(uasset|uexp|ubulk)$' }
foreach ($f in $files) {
    $relativePath = $f.FullName.Substring($COOKED_BASE.Length).TrimStart("\")
    # Mount inside the game's Content/, mirroring the cooked layout
    # (../../../OmegaStrikers/Content/<rel>) so /Game/<rel> resolves to ours.
    $mountPath = "../../../OmegaStrikers/Content/$relativePath"
    $mountPath = $mountPath -replace "\\", "/"
    $lines += "`"$($f.FullName)`" `"$mountPath`""
}

if ($lines.Count -eq 0) {
    Write-Fail "No files to package under $OVERRIDE_DIR"
    exit 1
}

Write-Ok "Found $($lines.Count) files"
foreach ($l in $lines) { Write-Host "    $l" -ForegroundColor DarkGray }

# UnrealPak's response file is read as ASCII (see package_logicmod.ps1 note).
$lines | Out-File -FilePath $RESPONSE_FILE -Encoding ascii

if (Test-Path $OUTPUT_PAK) {
    Remove-Item $OUTPUT_PAK -Force
    Write-Host "    Removed old pak" -ForegroundColor DarkGray
}

Write-Step "Running UnrealPak"
& $UNREALPAK $OUTPUT_PAK "-Create=$RESPONSE_FILE"

if ($LASTEXITCODE -eq 0 -and (Test-Path $OUTPUT_PAK)) {
    $pakSize = (Get-Item $OUTPUT_PAK).Length
    Write-Ok "Pak: $OUTPUT_PAK ($pakSize bytes)"
    Write-Host ""
    Write-Host "    Test recipe:" -ForegroundColor Cyan
    Write-Host "      1. Launch OS"
    Write-Host "      2. Home Hub -> Customize Striker -> Cosmetics tab -> Emote sub-tab"
    Write-Host "      3. PASS: red 'OSPLUS OVERRIDE OK' covers the panel"
    Write-Host "         FAIL (native renders): pak priority issue, investigate"
    Write-Host "         FAIL (empty/black):    parent class mismatch, fix in dev project"
    Write-Host "         FAIL (crash):          revert by deleting $OUTPUT_PAK"
} else {
    Write-Fail "UnrealPak failed (exit code: $LASTEXITCODE)"
    exit 1
}
