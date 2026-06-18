# THROWAWAY — Stage-3 Pass-2 A1 closing experiment, parent-class patch step.
#
# The dev project at F:\Omegamod\OmegaStonkers 5.1\ has no /Script/OdyUI
# module loaded, so we cooked WBP_Panel_StrikerEmoticons with parent
# `UserWidget` (the only thing the editor knows). UE5 runtime needs the
# parent class to be `OdyWidget` so the parent panel
# (WBP_Panel_StrikerCosmetics_C) can Cast<OdyWidget> + ProcessEvent its
# UFunctions on our widget without crashing.
#
# This script:
#   1. tojson    - cooked .uasset -> .json via UAssetGUI CLI
#   2. patch     - rewrite NameMap + Imports so the BPGC's SuperStruct
#                  resolves to /Script/OdyUI.OdyWidget at runtime
#   3. fromjson  - .json -> patched .uasset (overwrites the cooked file)
#
# After this runs, package_emoticons_override_test.ps1 paks the patched
# uasset normally.
#
# See: docs/features/emote-loadout-ui-improvement.md (Feasibility A1)
#      docs/learnings/customization-screen-widgetswitcher-architecture.md

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\_lib.ps1"

$WORKSPACE_ROOT = (Resolve-Path "$PSScriptRoot\..\..").Path
$UAGUI         = "$WORKSPACE_ROOT\tools\_bin\uassetgui\UAssetGUI.exe"
$COOKED_BASE   = "F:\Omegamod\OmegaStonkers 5.1\Saved\Cooked\Windows\OmegaStonkers\Content"
$UASSET_REL    = "Prometheus\UI\OutOfGame\Strikers\WBP_Panel_StrikerEmoticons.uasset"
$UASSET_PATH   = Join-Path $COOKED_BASE $UASSET_REL
$SCRATCH_DIR   = "$WORKSPACE_ROOT\scratch"
if (-not (Test-Path $SCRATCH_DIR)) { New-Item -ItemType Directory -Path $SCRATCH_DIR -Force | Out-Null }
$JSON_PATH     = "$SCRATCH_DIR\WBP_Panel_StrikerEmoticons.patched.json"
$BACKUP_PATH   = "$UASSET_PATH.unpatched.bak"

if (-not (Test-Path $UAGUI))       { Write-Fail "UAssetGUI not found: $UAGUI"; exit 1 }
if (-not (Test-Path $UASSET_PATH)) { Write-Fail "Cooked uasset not found: $UASSET_PATH"; exit 1 }

# Keep a backup of the unpatched cook output so we can re-cook + repatch
# without redoing the editor cook every time.
if (-not (Test-Path $BACKUP_PATH)) {
    Copy-Item $UASSET_PATH $BACKUP_PATH
    Write-Host "    backup -> $BACKUP_PATH" -ForegroundColor DarkGray
} else {
    # Restore from backup so we always patch a clean cook output
    Copy-Item $BACKUP_PATH $UASSET_PATH -Force
    Write-Host "    restored from backup" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 1. tojson
# ---------------------------------------------------------------------------

Write-Step "tojson"
& $UAGUI tojson $UASSET_PATH $JSON_PATH VER_UE5_1 2>&1 | Out-Null
if (-not (Test-Path $JSON_PATH)) { Write-Fail "tojson failed"; exit 1 }
Write-Ok "$JSON_PATH"

# ---------------------------------------------------------------------------
# 2. patch
# ---------------------------------------------------------------------------

Write-Step "patching parent class UserWidget -> OdyWidget"

$json = Get-Content $JSON_PATH -Raw | ConvertFrom-Json

# Add NameMap entries (if missing)
$nm = [System.Collections.ArrayList]@($json.NameMap)
foreach ($n in @('/Script/OdyUI', 'OdyWidget', 'Default__OdyWidget')) {
    if (-not ($nm -contains $n)) {
        $nm.Add($n) | Out-Null
        Write-Host "    + NameMap: $n" -ForegroundColor DarkGray
    }
}
$json.NameMap = $nm

# Add a new Import for /Script/OdyUI (Package) at the end of the Imports list.
# Compute its 1-based negative index for reference resolution.
$imports = [System.Collections.ArrayList]@($json.Imports)
$odyPkgImport = [PSCustomObject]@{
    '$type'          = 'UAssetAPI.Import, UAssetAPI'
    ObjectName       = '/Script/OdyUI'
    OuterIndex       = 0
    ClassPackage     = '/Script/CoreUObject'
    ClassName        = 'Package'
    PackageName      = $null
    bImportOptional  = $false
}
$imports.Add($odyPkgImport) | Out-Null
$odyPkgRef = -($imports.Count)  # 1-based negative ref to the freshly-added import
Write-Host "    + Import: /Script/OdyUI (Package) at ref $odyPkgRef" -ForegroundColor DarkGray

# Mutate existing UserWidget + Default__UserWidget imports in place.
# Their index doesn't change, so SuperIndex/SuperStruct refs stay valid;
# only the resolved name + outer change.
$mutated = 0
for ($i = 0; $i -lt $imports.Count; $i++) {
    $imp = $imports[$i]
    if ($imp.ObjectName -eq 'UserWidget' -and $imp.ClassName -eq 'Class') {
        $imp.ObjectName = 'OdyWidget'
        $imp.OuterIndex = $odyPkgRef
        Write-Host "    ~ Imports[$i]: UserWidget -> OdyWidget (outer -> /Script/OdyUI)" -ForegroundColor DarkGray
        $mutated++
    } elseif ($imp.ObjectName -eq 'Default__UserWidget') {
        $imp.ObjectName    = 'Default__OdyWidget'
        $imp.OuterIndex    = $odyPkgRef
        $imp.ClassPackage  = '/Script/OdyUI'
        $imp.ClassName     = 'OdyWidget'
        Write-Host "    ~ Imports[$i]: Default__UserWidget CDO -> Default__OdyWidget (outer -> /Script/OdyUI)" -ForegroundColor DarkGray
        $mutated++
    }
}
$json.Imports = $imports

if ($mutated -ne 2) {
    Write-Fail "expected to mutate 2 imports (UserWidget, Default__UserWidget) but mutated $mutated"
    exit 1
}

$json | ConvertTo-Json -Depth 64 -Compress:$false | Out-File $JSON_PATH -Encoding utf8
Write-Ok "patched JSON"

# ---------------------------------------------------------------------------
# 3. fromjson  (overwrite cooked uasset in place)
# ---------------------------------------------------------------------------

Write-Step "fromjson"
& $UAGUI fromjson $JSON_PATH $UASSET_PATH 2>&1 | Out-Null
if (-not (Test-Path $UASSET_PATH)) { Write-Fail "fromjson produced no file"; exit 1 }
$sz = (Get-Item $UASSET_PATH).Length
Write-Ok "$UASSET_PATH ($sz bytes)"

Write-Host ""
Write-Host "    Next: .\tools\test\package_emoticons_override_test.ps1" -ForegroundColor Cyan
