# OSPlus dev environment bootstrap.
# Idempotent — safe to re-run after any change.
#
# Installs:
#   - repak (UE pak inspector/extractor)
#   - UAssetGUI (UE .uasset parser, CLI mode)
#
# Verifies:
#   - tools/_bin/ exists with the binaries
#   - UE editor + UnrealPak.exe paths resolve
#   - Python plugins enabled in the UE project (best-effort; user confirms)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " OSPlus Dev Environment Bootstrap"        -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Tool downloads
# ---------------------------------------------------------------------------

& "$PSScriptRoot\install_repak.ps1"
& "$PSScriptRoot\install_uassetgui.ps1"

# ---------------------------------------------------------------------------
# 2. Verify UE Editor paths
# ---------------------------------------------------------------------------

Write-Host ""
Write-Step 'Verifying UE Editor + UnrealPak paths'

$UE_ROOT      = 'F:\UE510\UnrealEngine-5.1.0-release'
$UE_EDITOR    = "$UE_ROOT\Engine\Binaries\Win64\UnrealEditor.exe"
$UE_EDITOR_CMD= "$UE_ROOT\Engine\Binaries\Win64\UnrealEditor-Cmd.exe"
$UNREALPAK    = "$UE_ROOT\Engine\Binaries\Win64\UnrealPak.exe"
$PROJECT      = 'F:\Omegamod\OmegaStonkers 5.1\OmegaStonkers.uproject'

foreach ($p in @($UE_EDITOR, $UE_EDITOR_CMD, $UNREALPAK, $PROJECT)) {
    if (Test-Path $p) { Write-Ok "found: $p" }
    else              { Write-Fail "MISSING: $p" }
}

# ---------------------------------------------------------------------------
# 3. Verify UE Python plugin is enabled in the .uproject
# ---------------------------------------------------------------------------

Write-Host ""
Write-Step 'Verifying UE Python plugin is enabled'

if (Test-Path $PROJECT) {
    $proj = Get-Content $PROJECT -Raw | ConvertFrom-Json
    $plugins = if ($proj.Plugins) { $proj.Plugins } else { @() }

    $needed = @('PythonScriptPlugin', 'EditorScriptingUtilities')
    foreach ($p in $needed) {
        $entry = $plugins | Where-Object { $_.Name -eq $p }
        if ($entry -and $entry.Enabled -eq $true) {
            Write-Ok "$p enabled in .uproject"
        } elseif ($entry) {
            Write-Warn2 "$p PRESENT but Enabled=$($entry.Enabled) — flip to true in editor"
        } else {
            Write-Warn2 "$p NOT in .uproject — open editor, Edit > Plugins, enable + restart"
        }
    }
} else {
    Write-Warn2 'Cannot verify plugins — .uproject not found at expected path'
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Bootstrap complete"                       -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Installed binaries:" -ForegroundColor White
Get-ChildItem (Join-Path $BIN_DIR '*\*.exe') -ErrorAction SilentlyContinue | ForEach-Object {
    $size = [math]::Round($_.Length / 1MB, 2)
    Write-Host "  $($_.FullName) ($size MB)"
}

Write-Host ""
Write-Host "Next:" -ForegroundColor White
Write-Host "  - tools/setup/extract_game_paks.ps1   # one-shot, extract OS shipping content"
Write-Host "  - tools/ue/restructure_mod.py          # the OSPlus folder reorg (UE editor must be CLOSED)"
