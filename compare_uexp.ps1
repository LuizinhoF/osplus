$f1 = [System.IO.File]::ReadAllBytes("F:\Omegamod\OmegaStonkers\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OmegaStrikersMod\ModActor.uexp")
$f2 = [System.IO.File]::ReadAllBytes("F:\Omegamod\OmegaStonkers 5.1\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OmegaStrikersMod\ModActor.uexp")
Write-Host "ModActor.uexp - 5.1.1: $($f1.Length) bytes, 5.1.0: $($f2.Length) bytes"
$same = [System.Linq.Enumerable]::SequenceEqual([byte[]]$f1, [byte[]]$f2)
Write-Host "Identical: $same"
Write-Host ""

$f3 = [System.IO.File]::ReadAllBytes("F:\Omegamod\OmegaStonkers\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OmegaStrikersMod\ModActor.uasset")
$f4 = [System.IO.File]::ReadAllBytes("F:\Omegamod\OmegaStonkers 5.1\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OmegaStrikersMod\ModActor.uasset")
Write-Host "ModActor.uasset - 5.1.1: $($f3.Length) bytes, 5.1.0: $($f4.Length) bytes"
$same2 = [System.Linq.Enumerable]::SequenceEqual([byte[]]$f3, [byte[]]$f4)
Write-Host "Identical: $same2"
Write-Host ""

$w1 = [System.IO.File]::ReadAllBytes("F:\Omegamod\OmegaStonkers\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OmegaStrikersMod\WBP_ModChat.uexp")
$w2 = [System.IO.File]::ReadAllBytes("F:\Omegamod\OmegaStonkers 5.1\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OmegaStrikersMod\WBP_ModChat.uexp")
Write-Host "WBP_ModChat.uexp - 5.1.1: $($w1.Length) bytes, 5.1.0: $($w2.Length) bytes"
Write-Host ""

Write-Host "=== Searching for bad FName index 33817088 (0x02040480) in 5.1.0 WBP_ModChat.uexp ==="
$target = [byte[]]@(0x80, 0x04, 0x04, 0x02)
for ($i = 0; $i -le $w2.Length - 4; $i++) {
    if ($w2[$i] -eq $target[0] -and $w2[$i+1] -eq $target[1] -and $w2[$i+2] -eq $target[2] -and $w2[$i+3] -eq $target[3]) {
        Write-Host "  FOUND at offset $i (0x$([Convert]::ToString($i, 16)))"
        $context = $w2[([Math]::Max(0,$i-8))..([Math]::Min($w2.Length-1,$i+11))]
        $hexStr = ($context | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
        Write-Host "  Context: $hexStr"
    }
}

Write-Host ""
Write-Host "=== Also checking if it's in the uasset ==="
$wa2 = [System.IO.File]::ReadAllBytes("F:\Omegamod\OmegaStonkers 5.1\Saved\Cooked\Windows\OmegaStonkers\Content\Mods\OmegaStrikersMod\WBP_ModChat.uasset")
for ($i = 0; $i -le $wa2.Length - 4; $i++) {
    if ($wa2[$i] -eq $target[0] -and $wa2[$i+1] -eq $target[1] -and $wa2[$i+2] -eq $target[2] -and $wa2[$i+3] -eq $target[3]) {
        Write-Host "  FOUND at offset $i (0x$([Convert]::ToString($i, 16)))"
    }
}
Write-Host "Done."
