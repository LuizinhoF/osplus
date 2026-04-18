# Extract / inventory Omega Strikers' shipping pak files for static RE.
#
# Default mode is INVENTORY (fast, ~seconds): list every file inside every
# game pak, save to data/re/raw/pak-inventory/. Lets us see what content
# the game ships without spending disk on a full extract.
#
# Pass -Extract to do a full unpack to scratch/game-paks-extracted/.
# That's slow (minutes), eats ~5-10 GB, and is gitignored. Only do it
# when we actually want to read .uasset bytes.
#
# Pass -Filter "Content/UI/*" to extract only matching paths.

[CmdletBinding()]
param(
    [switch]$Extract,
    [string]$Filter,
    [string]$GamePaksDir = 'F:\SteamLibrary\steamapps\common\OmegaStrikers\OmegaStrikers\Content\Paks'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_lib.ps1"

$REPAK = Join-Path $BIN_DIR 'repak\repak.exe'
$INV_DIR = Join-Path $WORKSPACE_ROOT 'data\re\raw\pak-inventory'
$EXTRACT_DIR = Join-Path $WORKSPACE_ROOT 'scratch\game-paks-extracted'

Write-Step "Inventorying game paks at $GamePaksDir"

if (-not (Test-Path $REPAK))       { Write-Fail "repak not installed — run tools/setup/bootstrap.ps1"; exit 1 }
if (-not (Test-Path $GamePaksDir)) { Write-Fail "Game paks dir not found: $GamePaksDir"; exit 1 }

# Find all paks EXCEPT our own LogicMods/
$paks = Get-ChildItem -Path $GamePaksDir -Filter '*.pak' -Recurse |
        Where-Object { $_.FullName -notmatch '\\LogicMods\\' }

if ($paks.Count -eq 0) {
    Write-Fail "No game paks found at $GamePaksDir"
    exit 1
}

Write-Ok "Found $($paks.Count) game pak(s):"
foreach ($p in $paks) {
    $sizeMB = [math]::Round($p.Length / 1MB, 1)
    Write-Host "    $($p.Name) ($sizeMB MB)"
}

# ---------------------------------------------------------------------------
# Inventory pass — always runs
# ---------------------------------------------------------------------------

if (-not (Test-Path $INV_DIR)) { New-Item -ItemType Directory -Path $INV_DIR -Force | Out-Null }

Write-Host ''
Write-Step 'Listing pak contents'

$totalFiles = 0
foreach ($pak in $paks) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($pak.Name)
    $listOut = Join-Path $INV_DIR "$base.list.txt"
    $infoOut = Join-Path $INV_DIR "$base.info.txt"

    Write-Host "    $($pak.Name) ..." -NoNewline -ForegroundColor DarkGray
    & $REPAK info  $pak.FullName 2>&1 | Out-File $infoOut -Encoding utf8
    & $REPAK list  $pak.FullName 2>&1 | Out-File $listOut -Encoding utf8

    if ($LASTEXITCODE -ne 0) {
        # Likely encrypted — repak prints a key request error
        Write-Host ' FAILED' -ForegroundColor Red
        $errMsg = Get-Content $listOut -Raw
        Write-Warn2 "repak failed for $($pak.Name) — likely AES-encrypted."
        Write-Host "    Error: $($errMsg.Trim())" -ForegroundColor DarkGray
        Write-Host "    If encrypted, find the AES key (community wikis / fmodel) and re-run with:" -ForegroundColor DarkGray
        Write-Host "      `$env:REPAK_AES_KEY = '0x...'; .\tools\setup\extract_game_paks.ps1" -ForegroundColor DarkGray
        continue
    }

    $count = (Get-Content $listOut | Measure-Object -Line).Lines
    $totalFiles += $count
    Write-Host " $count files" -ForegroundColor Green
}

Write-Host ''
Write-Ok "Inventory written to $INV_DIR ($totalFiles files indexed)"

# ---------------------------------------------------------------------------
# Top-level category summary — what kinds of content exist?
# ---------------------------------------------------------------------------

Write-Host ''
Write-Step 'Top-level content categories (first 25)'

$catCounts = @{}
Get-ChildItem $INV_DIR -Filter '*.list.txt' | ForEach-Object {
    Get-Content $_.FullName | ForEach-Object {
        # repak list output is a path per line; pull first 2-3 path segments
        $parts = $_.Trim() -split '/'
        if ($parts.Count -ge 2) {
            $key = ($parts[0..([Math]::Min(2, $parts.Count - 1))] -join '/')
            if ($catCounts.ContainsKey($key)) { $catCounts[$key] = $catCounts[$key] + 1 }
            else                              { $catCounts[$key] = 1 }
        }
    }
}

$catCounts.GetEnumerator() |
    Sort-Object -Property Value -Descending |
    Select-Object -First 25 |
    ForEach-Object { Write-Host ("    {0,7}  {1}" -f $_.Value, $_.Key) }

# ---------------------------------------------------------------------------
# Optional extract pass
# ---------------------------------------------------------------------------

if ($Extract) {
    Write-Host ''
    Write-Step 'Extracting pak contents (this may take a while)'

    if (-not (Test-Path $EXTRACT_DIR)) { New-Item -ItemType Directory -Path $EXTRACT_DIR -Force | Out-Null }

    foreach ($pak in $paks) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($pak.Name)
        $dest = Join-Path $EXTRACT_DIR $base

        Write-Host "    extracting $($pak.Name) -> $dest" -ForegroundColor DarkGray
        if ($Filter) {
            & $REPAK unpack --output $dest --include $Filter $pak.FullName
        } else {
            & $REPAK unpack --output $dest $pak.FullName
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Warn2 "extract failed for $($pak.Name) (see output above)"
        } else {
            $extractSize = (Get-ChildItem $dest -Recurse -File | Measure-Object Length -Sum).Sum
            $sizeMB = [math]::Round($extractSize / 1MB, 1)
            Write-Ok "extracted to $dest ($sizeMB MB)"
        }
    }
}

Write-Host ''
Write-Host 'Done. Inventory ready for grep:' -ForegroundColor White
Write-Host "  Get-ChildItem $INV_DIR" -ForegroundColor DarkGray
Write-Host '  rg "Pattern" data\re\raw\pak-inventory\' -ForegroundColor DarkGray
