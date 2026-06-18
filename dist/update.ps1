param(
    [string]$Repo = "LuizinhoF/osplus",
    [string]$AssetName = "OSPlus.zip"
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevated {
    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-Repo", "`"$Repo`"",
        "-AssetName", "`"$AssetName`""
    )
    Start-Process -FilePath "powershell" -ArgumentList $args -Verb RunAs
}

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "           OSPlus - Updater" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-IsAdmin)) {
    Write-Host "[!] Requesting administrator privileges..."
    Invoke-SelfElevated
    exit 0
}

$downloadUrl = "https://github.com/$Repo/releases/latest/download/$AssetName"
$tempRoot = Join-Path $env:TEMP ("osplus-update-" + [guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $tempRoot $AssetName
$extractDir = Join-Path $tempRoot "package"

try {
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $extractDir -ItemType Directory -Force | Out-Null

    Write-Host "Downloading latest OSPlus release..."
    Write-Host "  $downloadUrl"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

    Write-Host "Extracting package..."
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    $installer = Join-Path $extractDir "install.bat"
    if (-not (Test-Path $installer)) {
        throw "Downloaded package does not contain install.bat"
    }

    Write-Host "Running installer..."
    $proc = Start-Process -FilePath $installer -WorkingDirectory $extractDir -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        throw "Installer failed with exit code $($proc.ExitCode)"
    }

    Write-Host ""
    Write-Host "[OK] OSPlus is up to date." -ForegroundColor Green
} finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
