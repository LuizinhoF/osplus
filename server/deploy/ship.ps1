#
# ship.ps1 — push the relay to the OCI VM and (re)install it.
#
# Usage from the project root:
#   .\server\deploy\ship.ps1
#
# Optional overrides:
#   .\server\deploy\ship.ps1 -Host 1.2.3.4 -KeyPath ~/.ssh/other.key
#

[CmdletBinding()]
param(
    [string] $VmHost = "136.248.104.200",
    [string] $User    = "ubuntu",
    [string] $KeyPath = "$env:USERPROFILE\.ssh\osplus_oci.key",
    [string] $RemoteStaging = "/tmp/osplus-deploy"
)

$ErrorActionPreference = "Stop"

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
Write-Host "[ship] preparing remote staging dir"
& ssh @sshArgs "rm -rf $RemoteStaging && mkdir -p $RemoteStaging/server"
if ($LASTEXITCODE -ne 0) { throw "remote prep failed" }

# 2. Copy what install-relay.sh expects (index.js, package*.json, deploy/*).
#    We deliberately avoid copying node_modules — install-relay.sh re-runs npm install on the VM.
Write-Host "[ship] uploading code"
$filesToShip = @(
    "$serverDir\index.js",
    "$serverDir\package.json",
    "$serverDir\package-lock.json"
) | Where-Object { Test-Path $_ }

foreach ($f in $filesToShip) {
    & scp -i $KeyPath -o "StrictHostKeyChecking=accept-new" $f "${User}@${VmHost}:$RemoteStaging/server/"
    if ($LASTEXITCODE -ne 0) { throw "scp failed for $f" }
}

# 3. Copy the deploy/ subfolder.
Write-Host "[ship] uploading deploy/"
& scp -i $KeyPath -o "StrictHostKeyChecking=accept-new" -r "$serverDir\deploy" "${User}@${VmHost}:$RemoteStaging/server/"
if ($LASTEXITCODE -ne 0) { throw "scp deploy/ failed" }

# 3b. Normalize line endings on remote side. Files written from Windows often
#     end up with CRLF; bash chokes on the trailing \r in shell scripts and
#     systemd is happier without them in unit files. dos2unix would be ideal
#     but isn't installed by default on Oracle's Ubuntu image, so use sed.
Write-Host "[ship] normalizing line endings (CRLF -> LF) on remote"
& ssh @sshArgs "find $RemoteStaging/server -type f \( -name '*.sh' -o -name '*.service' -o -name 'Caddyfile' -o -name '*.js' -o -name '*.json' \) -exec sed -i 's/\r`$//' {} +"
if ($LASTEXITCODE -ne 0) { throw "line-ending normalization failed" }

# 4. Run the installer.
Write-Host "[ship] running install-relay.sh on VM"
& ssh @sshArgs "sudo bash $RemoteStaging/server/deploy/install-relay.sh"
if ($LASTEXITCODE -ne 0) { throw "install-relay.sh failed" }

Write-Host ""
Write-Host "[ship] done."
Write-Host "[ship] public health: https://play-osplus.duckdns.org/health"
