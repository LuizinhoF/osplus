param([string]$FilePath, [string]$Label)

$bytes = [System.IO.File]::ReadAllBytes($FilePath)
$reader = New-Object System.IO.BinaryReader([System.IO.MemoryStream]::new($bytes))

Write-Host "=== $Label ===" -ForegroundColor Cyan
Write-Host "File: $FilePath"
Write-Host "Size: $($bytes.Length) bytes"
Write-Host ""

$tag = $reader.ReadUInt32()
Write-Host ("Tag: 0x{0:X8}" -f $tag)

$legacyVer = $reader.ReadInt32()
Write-Host "LegacyFileVersion: $legacyVer"

$legacyUE3 = $reader.ReadInt32()
Write-Host "LegacyUE3Version: $legacyUE3"

$fileVerUE4 = $reader.ReadInt32()
Write-Host "FileVersionUE4: $fileVerUE4"

$fileVerUE5 = $reader.ReadInt32()
Write-Host "FileVersionUE5: $fileVerUE5"

$fileVerLicensee = $reader.ReadInt32()
Write-Host "FileVersionLicensee: $fileVerLicensee"

$customVerCount = $reader.ReadInt32()
Write-Host "CustomVersions count: $customVerCount"

for ($i = 0; $i -lt $customVerCount; $i++) {
    $guidBytes = $reader.ReadBytes(16)
    $guid = [System.Guid]::new($guidBytes)
    $ver = $reader.ReadInt32()
    if ($i -lt 5) { Write-Host "  CV[$i]: $guid = $ver" }
}
if ($customVerCount -gt 5) { Write-Host "  ... ($customVerCount total)" }

$totalHeaderSize = $reader.ReadInt32()
Write-Host "TotalHeaderSize: $totalHeaderSize"

$folderNameLen = $reader.ReadInt32()
if ($folderNameLen -gt 0) {
    $folderNameBytes = $reader.ReadBytes($folderNameLen)
    $folderName = [System.Text.Encoding]::ASCII.GetString($folderNameBytes).TrimEnd([char]0)
} elseif ($folderNameLen -lt 0) {
    $unicodeLen = -$folderNameLen
    $folderNameBytes = $reader.ReadBytes($unicodeLen * 2)
    $folderName = [System.Text.Encoding]::Unicode.GetString($folderNameBytes).TrimEnd([char]0)
} else {
    $folderName = ""
}
Write-Host "FolderName: '$folderName'"

$packageFlags = $reader.ReadUInt32()
Write-Host ("PackageFlags: 0x{0:X8}" -f $packageFlags)

$nameCount = $reader.ReadInt32()
$nameOffset = $reader.ReadInt32()
Write-Host "NameCount: $nameCount (offset: $nameOffset)"

$softObjCount = $reader.ReadInt32()
$softObjOffset = $reader.ReadInt32()
Write-Host "SoftObjectPaths: count=$softObjCount offset=$softObjOffset"

$gatherableCount = $reader.ReadInt32()
$gatherableOffset = $reader.ReadInt32()
Write-Host "GatherableTextData: count=$gatherableCount offset=$gatherableOffset"

$exportCount = $reader.ReadInt32()
$exportOffset = $reader.ReadInt32()
Write-Host "ExportCount: $exportCount (offset: $exportOffset)"

$importCount = $reader.ReadInt32()
$importOffset = $reader.ReadInt32()
Write-Host "ImportCount: $importCount (offset: $importOffset)"

$dependsOffset = $reader.ReadInt32()
Write-Host "DependsOffset: $dependsOffset"

Write-Host ""
Write-Host "--- FName Table ($nameCount entries at offset $nameOffset) ---"
$reader.BaseStream.Position = $nameOffset
for ($i = 0; $i -lt $nameCount; $i++) {
    $pos = $reader.BaseStream.Position
    $strLen = $reader.ReadInt32()
    if ($strLen -gt 0 -and $strLen -lt 1024) {
        $strBytes = $reader.ReadBytes($strLen)
        $str = [System.Text.Encoding]::ASCII.GetString($strBytes).TrimEnd([char]0)
    } elseif ($strLen -lt 0 -and $strLen -gt -1024) {
        $unicodeLen = -$strLen
        $strBytes = $reader.ReadBytes($unicodeLen * 2)
        $str = [System.Text.Encoding]::Unicode.GetString($strBytes).TrimEnd([char]0)
    } else {
        $str = "<invalid length: $strLen>"
        break
    }
    $hash1 = $reader.ReadUInt16()
    $hash2 = $reader.ReadUInt16()
    Write-Host ("  [{0,3}] '{1}'" -f $i, $str)
}

$reader.Close()
