param(
    [string]$Repo = "LuizinhoF/osplus",
    [string]$ManifestPath = "$PSScriptRoot\..\..\dist\version.json",
    [switch]$SkipBuild,
    [switch]$Draft,
    [switch]$Prerelease,
    [switch]$AllowNonMain
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\_lib.ps1"

$ROOT = Resolve-Path "$PSScriptRoot\..\.."
$manifest = Get-Content -Raw $ManifestPath | ConvertFrom-Json
$version = [string]$manifest.version
$assetName = [string]$manifest.release_asset
$tagName = "v$version"
$zipPath = Join-Path $ROOT "dist\$assetName"

if (-not $version) {
    throw "dist/version.json is missing a version."
}

if (-not $assetName) {
    throw "dist/version.json is missing release_asset."
}

$token = $env:GH_TOKEN
if (-not $token) { $token = $env:GITHUB_TOKEN }
if (-not $token) {
    throw "Set GH_TOKEN or GITHUB_TOKEN to a GitHub token with repo release permissions."
}

$branch = (& git -C $ROOT branch --show-current).Trim()
if ($branch -ne "main" -and -not $AllowNonMain) {
    throw "Releases must be published from main. Current branch: $branch"
}

$status = (& git -C $ROOT status --porcelain)
if ($status) {
    throw "Working tree is dirty. Commit or stash changes before publishing a release."
}

$commit = (& git -C $ROOT rev-parse HEAD).Trim()

if (-not $SkipBuild) {
    Write-Step "Building distribution package"
    Invoke-External "build_dist.ps1" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ROOT "build_dist.ps1")
    }
}

if (-not (Test-Path $zipPath)) {
    throw "Release zip not found: $zipPath"
}

$headers = @{
    "Authorization" = "Bearer $token"
    "Accept" = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
    "User-Agent" = "osplus-release-script"
}

$releaseBody = @"
OSPlus $version

Assets:
- $assetName

Install/update instructions are in README.md and docs/ops/github-release-distribution.md.
"@

$body = @{
    tag_name = $tagName
    target_commitish = $commit
    name = "OSPlus $version"
    body = $releaseBody
    draft = [bool]$Draft
    prerelease = [bool]$Prerelease
} | ConvertTo-Json

$releaseUrl = "https://api.github.com/repos/$Repo/releases"
Write-Step "Creating GitHub release $tagName"
try {
    $release = Invoke-RestMethod -Uri $releaseUrl -Method Post -Headers $headers -ContentType "application/json" -Body $body
} catch {
    $message = $_.Exception.Message
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 422) {
        Write-Warn2 "Release or tag $tagName already exists; using existing release."
        $release = Invoke-RestMethod -Uri "$releaseUrl/tags/$tagName" -Method Get -Headers $headers
    } else {
        throw $message
    }
}

$uploadBase = ($release.upload_url -replace "\{.*$", "")

function Remove-ExistingReleaseAsset {
    param([Parameter(Mandatory=$true)][string]$Name)

    $existing = @($release.assets | Where-Object { $_.name -eq $Name })
    foreach ($asset in $existing) {
        Write-Warn2 "Removing existing release asset $Name"
        Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/assets/$($asset.id)" -Method Delete -Headers $headers | Out-Null
    }
}

function Upload-ReleaseAsset {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$ContentType
    )

    Remove-ExistingReleaseAsset -Name $Name
    $escapedName = [uri]::EscapeDataString($Name)
    $url = "${uploadBase}?name=$escapedName"
    Write-Step "Uploading $Name"
    Invoke-RestMethod -Uri $url -Method Post -Headers $headers -ContentType $ContentType -InFile $Path | Out-Null
}

Upload-ReleaseAsset -Path $zipPath -Name $assetName -ContentType "application/zip"
Remove-ExistingReleaseAsset -Name "version.json"

Write-Ok "Release published: $($release.html_url)"
