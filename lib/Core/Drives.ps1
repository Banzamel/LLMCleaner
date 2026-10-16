<#
    LLMCleaner - choosing drives to scan
#>

# Local fixed drives with a letter. Skipped: USB/cards (DriveType 2), network (4), CD (5), partitions without a letter
# (EFI, Recovery) and unavailable volumes, e.g. locked by BitLocker (no size).
function Get-FixedDrives { Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object { $_.Size -gt 0 } }

# Drives chosen by the user. The system drive is always scanned (Windows cache, profile,
# Program Files); the others affect the Recycle Bin, Steam/Epic libraries and space analysis.
$script:SelectedDrives = @($Sys)
function Get-SelectedDrives { Get-FixedDrives | Where-Object { $_.DeviceID -in $script:SelectedDrives } }
function Test-OnSelectedDrive([string]$p) { $p.Length -ge 2 -and $p.Substring(0, 2).ToUpper() -in $script:SelectedDrives }
function Set-SelectedDrives([string[]]$letters) {
    $all = @(Get-FixedDrives | ForEach-Object { $_.DeviceID })
    $script:SelectedDrives = @(@($Sys) + @($letters | ForEach-Object { $_ -split ',' } | Where-Object { $_ } |
                ForEach-Object { $_.Trim().TrimEnd(':', '\').ToUpper() + ':' }) | Where-Object { $_ -in $all } | Select-Object -Unique)
}
function Format-Drive($d) {
    $name = if ($d.VolumeName) { $d.VolumeName } else { L 'bez nazwy' 'no label' }
    (L '{0} {1} - wolne {2} z {3}' '{0} {1} - {2} free of {3}') -f $d.DeviceID, $name, (Format-Size $d.FreeSpace), (Format-Size $d.Size)
}

# User's Recycle Bin on each selected drive: X:\$Recycle.Bin\<SID>
function Get-RecycleBinFolders { foreach ($d in Get-SelectedDrives) { $p = "$($d.DeviceID)\`$Recycle.Bin\$UserSid"; if (Test-Path -LiteralPath $p) { $p } } }
