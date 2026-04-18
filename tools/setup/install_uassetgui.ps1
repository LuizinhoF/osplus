# Install UAssetGUI: the community-standard UE .uasset inspector/parser by atenfyr.
# Repo: https://github.com/atenfyr/UAssetGUI
#
# Has both a GUI mode (we don't use) and a CLI mode (we DO use):
#   UAssetGUI tojson <input.uasset> <output.json> <UE version>
#   UAssetGUI fromjson <input.json> <output.uasset>
#
# Newer releases (v1.0.3+) ship a single self-contained UAssetGUI.exe.
# Older releases shipped UAssetGUI.zip. We handle both.

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"

Write-Step 'Installing UAssetGUI'

$REPO     = 'atenfyr/UAssetGUI'
$DEST_DIR = Join-Path $BIN_DIR 'uassetgui'

$release = Get-LatestRelease -Owner ($REPO -split '/')[0] -Repo ($REPO -split '/')[1]
Write-Host "    latest release: $($release.tag_name) ($($release.published_at))" -ForegroundColor DarkGray

if (Test-Path $DEST_DIR) { Remove-Item -Recurse -Force $DEST_DIR }
New-Item -ItemType Directory -Path $DEST_DIR -Force | Out-Null

# Prefer single-exe build (newer), fall back to zip (older releases).
$assets = $release.assets
$exeAsset = $assets | Where-Object { $_.name -match '^UAssetGUI\.exe$' } | Select-Object -First 1
$zipAsset = $assets | Where-Object { $_.name -match '^UAssetGUI\.zip$' } | Select-Object -First 1

if ($exeAsset) {
    $dest = Join-Path $DEST_DIR 'UAssetGUI.exe'
    Write-Host "    downloading $($exeAsset.name) ($([math]::Round($exeAsset.size / 1MB, 2)) MB)..." -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $exeAsset.browser_download_url -OutFile $dest -UseBasicParsing
} elseif ($zipAsset) {
    $archive = Download-Release -Asset $zipAsset
    Expand-To -ArchivePath $archive -TargetDir $DEST_DIR
    Remove-Item $archive -Force
} else {
    $allNames = ($assets | ForEach-Object { $_.name }) -join "`n      "
    throw "No suitable UAssetGUI asset found. Available:`n      $allNames"
}

$exe = Get-ChildItem -Path $DEST_DIR -Recurse -Filter 'UAssetGUI.exe' | Select-Object -First 1
if (-not $exe) { Write-Fail 'UAssetGUI.exe not found after install'; exit 1 }

Write-Ok "UAssetGUI installed: $($exe.FullName)"
Write-Ok "release: $($release.tag_name)"
Write-Host "    Note: this exe is BOTH a GUI and a CLI. Always invoke with subcommand args." -ForegroundColor DarkGray
Write-Host "    Example: & '$($exe.FullName)' tojson input.uasset output.json VER_UE5_1" -ForegroundColor DarkGray
