# stop hook — remind about the learnings-discipline rule at the end of a
# non-trivial session.
#
# Why: docs/learnings/ is OSPlus's compounding mechanism. The always-applied
# learnings-discipline rule says to write one before declaring a task done.
# This hook surfaces a reminder on agent stop when the current branch is not
# main AND no new/modified file under docs/learnings/ is in git status — a
# heuristic for "work happened, nothing captured."
#
# Contract (Cursor hooks v1):
#   stdin  : JSON with fields {status: "completed|aborted|error", ...}
#   stdout : informational only (shows in Cursor's Hooks output channel)

$ErrorActionPreference = "Continue"

$stdin = [Console]::In.ReadToEnd()
$event = $null
try { $event = $stdin | ConvertFrom-Json } catch { exit 0 }

if ($event.status -ne "completed") { exit 0 }

$branch = (& git rev-parse --abbrev-ref HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or $branch -eq "main" -or -not $branch) { exit 0 }

# Status porcelain: look for any entry under docs/learnings/ that isn't the README or template.
$status = & git status --porcelain docs/learnings/ 2>$null
$hasLearning = $false
foreach ($line in ($status -split "`n")) {
    if ($line -match 'docs/learnings/(?!README\.md|_TEMPLATE\.md)[^ ]+\.md') {
        $hasLearning = $true; break
    }
}

if (-not $hasLearning) {
    Write-Host "[hook-learnings-reminder] Branch '$branch' but no new/changed file under docs/learnings/."
    Write-Host "  If this work hit any trigger in .cursor/rules/learnings-discipline.mdc, write one before declaring done."
    Write-Host "  Template: docs/learnings/_TEMPLATE.md"
}

exit 0
