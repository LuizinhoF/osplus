# Install repak: the community-standard UE pak inspector/extractor by trumank.
# Repo: https://github.com/trumank/repak
#
# Pulls the latest x86_64-pc-windows-msvc release, extracts repak.exe into
# tools/_bin/repak/, and runs `repak --version` to confirm.

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"

Write-Step 'Installing repak'

$REPO     = 'trumank/repak'
$DEST_DIR = Join-Path $BIN_DIR 'repak'

$release = Get-LatestRelease -Owner ($REPO -split '/')[0] -Repo ($REPO -split '/')[1]
Write-Host "    latest release: $($release.tag_name) ($($release.published_at))" -ForegroundColor DarkGray

# Asset is named like: repak_cli-x86_64-pc-windows-msvc.zip
$asset = Find-ReleaseAsset -Release $release -NamePattern 'x86_64-pc-windows-msvc\.zip$'
$archive = Download-Release -Asset $asset
Expand-To -ArchivePath $archive -TargetDir $DEST_DIR
Remove-Item $archive -Force

# Locate the actual exe (sometimes inside a subfolder)
$exe = Get-ChildItem -Path $DEST_DIR -Recurse -Filter 'repak.exe' | Select-Object -First 1
if (-not $exe) { Write-Fail "repak.exe not found in extracted archive"; exit 1 }

# If exe is in a subfolder, move it up so the path is stable
if ($exe.DirectoryName -ne $DEST_DIR) {
    Move-Item $exe.FullName $DEST_DIR -Force
}
$exePath = Join-Path $DEST_DIR 'repak.exe'

$version = & $exePath --version 2>&1
Write-Ok  "repak installed: $exePath"
Write-Ok  "version: $version"
