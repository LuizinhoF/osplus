# afterFileEdit hook — warn if a hardcoded F:\ path was introduced in a file
# that isn't part of the known "scope-debt" allowlist.
#
# Why: powershell-conventions.mdc defines a narrow list of build/deploy scripts
# that are allowed to hardcode F:\Omegamod\..., F:\UE510\..., F:\SteamLibrary\...
# paths (single-dev machine, not parameterizable without YAGNI tax). Any *other*
# file picking up the same pattern is scope-drift and needs review.
#
# Contract (Cursor hooks v1):
#   stdin  : JSON with fields {file_path, edits:[{old_string, new_string}], ...}
#   stdout : informational only (shows in Cursor's Hooks output channel)

$ErrorActionPreference = "Stop"

# Files where hardcoded F:\ paths are an accepted policy.
$allowlist = @(
    "build_dist.ps1",
    "deploy.ps1",
    "package_logicmod.ps1",
    "package_pak.ps1",
    "parse_uasset.ps1",
    "compare_uexp.ps1"
)

$stdin = [Console]::In.ReadToEnd()
$event = $null
try { $event = $stdin | ConvertFrom-Json } catch { exit 0 }

$filePath = [string]$event.file_path
if (-not $filePath) { exit 0 }

$leaf = Split-Path $filePath -Leaf
if ($allowlist -contains $leaf) { exit 0 }

foreach ($edit in @($event.edits)) {
    $added = [string]$edit.new_string
    if ($added -match '(?i)F:\\(Omegamod|UE510|SteamLibrary)') {
        Write-Host "[hook-hardcoded-path] WARNING: new 'F:\...' reference in $filePath is outside the allowlist."
        Write-Host "  See .cursor/rules/powershell-conventions.mdc -> 'Hardcoded F:\\ paths'."
        Write-Host "  If this file legitimately needs the path, add it to the allowlist in this hook."
        break
    }
}

exit 0
