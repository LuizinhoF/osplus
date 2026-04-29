#
# ship.ps1 — push the relay to the OCI VM and (re)install it.
#
# Usage from the project root:
#   .\server\deploy\ship.ps1
#
# Optional overrides:
#   .\server\deploy\ship.ps1 -VmHost 1.2.3.4 -KeyPath ~/.ssh/other.key
#

[CmdletBinding()]
param(
    [string] $VmHost = "136.248.104.200",
    [string] $User    = "ubuntu",
    [string] $KeyPath = "$env:USERPROFILE\.ssh\osplus_oci.key",
    [string] $RemoteStaging = "/tmp/osplus-deploy"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\..\tools\_lib.ps1"

# Resolve the local server/ directory based on this script's location.
$serverDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$serverDir = $serverDir.Path

Write-Host "[ship] local source : $serverDir"
Write-Host "[ship] target       : $User@${VmHost}:$RemoteStaging"
Write-Host "[ship] ssh key      : $KeyPath"

if (-not (Test-Path $KeyPath)) {
    throw "SSH key not found at $KeyPath"
}

$sshArgs = @(
    "-i", $KeyPath,
    "-o", "StrictHostKeyChecking=accept-new",
    "$User@$VmHost"
)

# 1. Reset remote staging dir.
Write-Step "Preparing remote staging dir"
Invoke-External "remote prep" { & ssh @sshArgs "rm -rf $RemoteStaging && mkdir -p $RemoteStaging/server" }

# 2. Copy what install-relay.sh expects (index.js, package*.json, deploy/*).
#    We deliberately avoid copying node_modules — install-relay.sh re-runs
#    npm install on the VM.
Write-Step "Uploading code"
$filesToShip = @(
    "$serverDir\index.js",
    "$serverDir\package.json",
    "$serverDir\package-lock.json"
) | Where-Object { Test-Path $_ }

foreach ($f in $filesToShip) {
    Invoke-External "scp $f" {
        & scp -i $KeyPath -o "StrictHostKeyChecking=accept-new" $f "${User}@${VmHost}:$RemoteStaging/server/"
    }
}

# 3. Copy the deploy/ subfolder.
Write-Step "Uploading deploy/"
Invoke-External "scp deploy/" {
    & scp -i $KeyPath -o "StrictHostKeyChecking=accept-new" -r "$serverDir\deploy" "${User}@${VmHost}:$RemoteStaging/server/"
}

# 3a. Copy the api/ subfolder (persistence module — `index.js` requires
#     `./api`). When new sibling subdirectories are added under server/ in
#     the future, add them here AND in install-relay.sh's copy block, OR
#     refactor both to a single rsync-style sync. Both files must stay in
#     sync per .cursor/rules/harnesses.mdc.
Write-Step "Uploading api/"
Invoke-External "scp api/" {
    & scp -i $KeyPath -o "StrictHostKeyChecking=accept-new" -r "$serverDir\api" "${User}@${VmHost}:$RemoteStaging/server/"
}

# 3b. Normalize line endings on the remote side. Even with .gitattributes
#     enforcing LF on *.sh / *.service / Caddyfile, files can still end up
#     with CRLF if they were edited outside Git's normalization (e.g.
#     Notepad save). dos2unix would be ideal but isn't installed by default
#     on Oracle's Ubuntu image, so use sed. Belt + suspenders with
#     .gitattributes; see docs/learnings/oci-relay-deploy-gotchas.md.
Write-Step "Normalizing line endings (CRLF -> LF) on remote"
Invoke-External "line-ending normalization" {
    & ssh @sshArgs "find $RemoteStaging/server -type f \( -name '*.sh' -o -name '*.service' -o -name 'Caddyfile' -o -name '*.js' -o -name '*.json' \) -exec sed -i 's/\r`$//' {} +"
}

# 4. Run the installer.
Write-Step "Running install-relay.sh on VM"
Invoke-External "install-relay.sh" { & ssh @sshArgs "sudo bash $RemoteStaging/server/deploy/install-relay.sh" }

Write-Host ""
Write-Ok "Done."
Write-Host "[ship] public health: https://play-osplus.duckdns.org/health"
