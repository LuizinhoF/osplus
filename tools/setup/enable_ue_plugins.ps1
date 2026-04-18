# Enable Python Editor Script Plugin + Editor Scripting Utilities in the
# OmegaStonkers .uproject. These ship with the engine but require explicit
# project-level enablement to be available for headless commandlets.
#
# Idempotent — re-running just confirms current state.
# Backs up the .uproject before modifying.
#
# IMPORTANT: Close the UE Editor before running this. UE caches the .uproject
# on load; changes made while it's open get clobbered when it autosaves.

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"

Write-Step 'Enabling UE Python plugins in .uproject'

$PROJECT = 'F:\Omegamod\OmegaStonkers 5.1\OmegaStonkers.uproject'
$NEEDED  = @('PythonScriptPlugin', 'EditorScriptingUtilities')

if (-not (Test-Path $PROJECT)) { Write-Fail "Project not found: $PROJECT"; exit 1 }

# Refuse to write if UE is currently running
$ueProc = Get-Process -Name 'UnrealEditor' -ErrorAction SilentlyContinue
if ($ueProc) {
    Write-Fail 'UnrealEditor.exe is running — close it first, then re-run this script.'
    exit 1
}

# Read + parse
$raw  = Get-Content $PROJECT -Raw
$json = $raw | ConvertFrom-Json
if (-not $json.Plugins) {
    $json | Add-Member -NotePropertyName 'Plugins' -NotePropertyValue @() -Force
}

$existing = @{}
foreach ($p in $json.Plugins) { $existing[$p.Name] = $p }

$changed = $false
foreach ($name in $NEEDED) {
    if ($existing.ContainsKey($name)) {
        if ($existing[$name].Enabled -eq $true) {
            Write-Ok "$name already enabled"
        } else {
            $existing[$name].Enabled = $true
            $changed = $true
            Write-Ok "$name flipped Enabled=true"
        }
    } else {
        $entry = [pscustomobject]@{ Name = $name; Enabled = $true }
        $json.Plugins = @($json.Plugins) + $entry
        $changed = $true
        Write-Ok "$name added to Plugins"
    }
}

if (-not $changed) {
    Write-Host '    nothing to do — plugins were already enabled' -ForegroundColor DarkGray
    exit 0
}

# Backup, then write. UE prefers tab indents in .uproject by convention.
$backup = "$PROJECT.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item $PROJECT $backup -Force
Write-Host "    backup: $backup" -ForegroundColor DarkGray

$out = $json | ConvertTo-Json -Depth 10
# ConvertTo-Json defaults to 4-space indent; UE convention is tabs but accepts spaces.
[System.IO.File]::WriteAllText($PROJECT, $out, [System.Text.UTF8Encoding]::new($false))

Write-Ok "Wrote $PROJECT"
Write-Host "    Open the editor next time — both plugins will be enabled automatically." -ForegroundColor DarkGray
