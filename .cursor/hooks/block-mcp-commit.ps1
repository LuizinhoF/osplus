# beforeShellExecution hook — block git commands that would commit mcp.json.
#
# Why: .cursor/mcp.json is developer-machine-specific (absolute paths to MCP
# servers, API keys for hosted MCP endpoints). It is gitignored, but
# `git add -A`, `git add .`, or an explicit `git add **/mcp.json` can still
# commit it. This hook catches those and denies.
#
# Contract (Cursor hooks v1):
#   stdin  : JSON with fields {command, cwd, ...}
#   stdout : JSON {continue, permission, userMessage, agentMessage}
#   Informational fields are safe to omit; "permission" is the authoritative decision.

$ErrorActionPreference = "Stop"

$stdin = [Console]::In.ReadToEnd()
$event = $null
try { $event = $stdin | ConvertFrom-Json } catch { }

$cmd = if ($event) { [string]$event.command } else { "" }

# Allow everything that isn't a git write-path (add/commit/stash/checkout -- file).
# Allowlist is intentionally narrow so we don't paper over interesting commands.
$isGitWrite = $cmd -match '^\s*git\s+(add|commit|stash|checkout\s+--)\b'

if ($isGitWrite -and $cmd -match 'mcp\.json') {
    $msg = "Blocked: '$cmd' would touch mcp.json. That file is machine-specific (paths, keys) and must not be committed. Edit mcp.json.example instead, or exclude mcp.json from the add."
    @{
        continue      = $false
        permission    = "deny"
        userMessage   = $msg
        agentMessage  = $msg
    } | ConvertTo-Json -Compress
    exit 0
}

@{ continue = $true; permission = "allow" } | ConvertTo-Json -Compress
exit 0
