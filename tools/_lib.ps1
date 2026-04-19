# tools/_lib.ps1 — universal helpers for OSPlus PowerShell scripts.
#
# Dot-source this from any script that needs structured logging or
# external-command-with-exit-check helpers:
#
#   . "$PSScriptRoot\tools\_lib.ps1"            # from project root
#   . "$PSScriptRoot\..\tools\_lib.ps1"         # from a one-level subfolder
#   . "$PSScriptRoot\..\..\tools\_lib.ps1"      # from tools/setup/
#
# Conventions (also in .cursor/rules/powershell-conventions.mdc):
#   Write-Step  <msg>  "==> <msg>"        (cyan)   — major phase header
#   Write-Ok    <msg>  "    [ok] <msg>"   (green)  — success / completion
#   Write-Warn2 <msg>  "    [!] <msg>"    (yellow) — non-fatal warning
#   Write-Fail  <msg>  "    [fail] <msg>" (red)    — failure (caller decides exit/throw)
#
# (Write-Warn2 instead of Write-Warning to avoid colliding with PS's built-in
# Write-Warning, which has different semantics and respects $WarningPreference.)

function Write-Step([string]$msg)  { Write-Host "==> $msg"        -ForegroundColor Cyan }
function Write-Ok([string]$msg)    { Write-Host "    [ok] $msg"   -ForegroundColor Green }
function Write-Warn2([string]$msg) { Write-Host "    [!] $msg"    -ForegroundColor Yellow }
function Write-Fail([string]$msg)  { Write-Host "    [fail] $msg" -ForegroundColor Red }

# Invoke an external command and throw if it returns a non-zero exit code.
# This is the canonical workaround for the PowerShell footgun: setting
# $ErrorActionPreference = "Stop" does NOT trip on $LASTEXITCODE — only
# on PS-native errors. Every external invocation needs an explicit check.
#
# Usage:
#   Invoke-External "scp uploading deploy/" { & scp -i $key -r ./deploy "$user@$host:/tmp/" }
#
# The label appears in the thrown error so failures stay diagnosable.
function Invoke-External {
    param(
        [Parameter(Mandatory)] [string]   $Label,
        [Parameter(Mandatory)] [scriptblock] $ScriptBlock
    )
    & $ScriptBlock
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed (exit code: $LASTEXITCODE)"
    }
}
