# tools/setup/_lib.ps1 — bootstrap-specific helpers (GitHub releases,
# archive expansion). Dot-source this from setup scripts:
#
#   . "$PSScriptRoot\_lib.ps1"
#
# Pulls in the universal logging + Invoke-External helpers from tools/_lib.ps1.

. "$PSScriptRoot\..\_lib.ps1"

$script:WORKSPACE_ROOT = Resolve-Path "$PSScriptRoot\..\.."
$script:BIN_DIR        = Join-Path $WORKSPACE_ROOT 'tools\_bin'

# Get-LatestRelease: query GitHub releases API, return the parsed release object.
# Stops with a clear error if rate-limited or repo not found.
function Get-LatestRelease {
    param(
        [Parameter(Mandatory)] [string]$Owner,
        [Parameter(Mandatory)] [string]$Repo
    )
    $url = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    try {
        $headers = @{ 'User-Agent' = 'osplus-bootstrap'; 'Accept' = 'application/vnd.github+json' }
        return Invoke-RestMethod -Uri $url -Headers $headers -UseBasicParsing
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -eq 403) {
            throw "GitHub API rate-limited (60 req/hr unauthenticated). Wait ~1hr or set GH_TOKEN env var."
        }
        if ($status -eq 404) {
            throw "Repo not found: $Owner/$Repo"
        }
        throw "GitHub API error ($status) for $url : $($_.Exception.Message)"
    }
}

# Find-ReleaseAsset: pick the release asset whose name matches a regex.
# Errors clearly if zero or multiple match (caller should make pattern unique).
function Find-ReleaseAsset {
    param(
        [Parameter(Mandatory)] $Release,
        [Parameter(Mandatory)] [string]$NamePattern
    )
    $matches = @($Release.assets | Where-Object { $_.name -match $NamePattern })
    if ($matches.Count -eq 0) {
        $allNames = ($Release.assets | ForEach-Object { $_.name }) -join "`n      "
        throw "No release asset matched /$NamePattern/. Available assets:`n      $allNames"
    }
    if ($matches.Count -gt 1) {
        $names = ($matches | ForEach-Object { $_.name }) -join ', '
        throw "Multiple release assets matched /$NamePattern/: $names"
    }
    return $matches[0]
}

# Download-Release: fetch an asset to a temp path, return the path.
function Download-Release {
    param(
        [Parameter(Mandatory)] $Asset,
        [string]$DestDir = $env:TEMP
    )
    $dest = Join-Path $DestDir $Asset.name
    Write-Host "    downloading $($Asset.name) ($([math]::Round($Asset.size / 1MB, 2)) MB)..." -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $dest -UseBasicParsing
    return $dest
}

# Expand-To: clean target dir then expand archive into it.
function Expand-To {
    param(
        [Parameter(Mandatory)] [string]$ArchivePath,
        [Parameter(Mandatory)] [string]$TargetDir
    )
    if (Test-Path $TargetDir) { Remove-Item -Recurse -Force $TargetDir }
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    Expand-Archive -Path $ArchivePath -DestinationPath $TargetDir -Force
}
