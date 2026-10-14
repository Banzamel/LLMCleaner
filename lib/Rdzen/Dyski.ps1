<#
    LLMCleaner - wybor dyskow do skanowania
#>

# Lokalne dyski stale z litera. Pomijane: USB/karty (DriveType 2), sieciowe (4), CD (5), partycje bez litery
# (EFI, Recovery) i woluminy niedostepne, np. zablokowane BitLockerem (brak rozmiaru).
function DyskiStale { Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object { $_.Size -gt 0 } }

# Dyski wybrane przez uzytkownika. Dysk systemowy jest zawsze skanowany (cache Windows, profil,
# Program Files); pozostale wplywaja na Kosz, biblioteki Steam/Epic i analize miejsca.
$script:WybraneDyski = @($Sys)
function DyskiWybrane { DyskiStale | Where-Object { $_.DeviceID -in $script:WybraneDyski } }
function NaWybranymDysku([string]$p) { $p.Length -ge 2 -and $p.Substring(0, 2).ToUpper() -in $script:WybraneDyski }
function UstawDyski([string[]]$litery) {
    $wszystkie = @(DyskiStale | ForEach-Object { $_.DeviceID })
    $script:WybraneDyski = @(@($Sys) + @($litery | ForEach-Object { $_ -split ',' } | Where-Object { $_ } |
                ForEach-Object { $_.Trim().TrimEnd(':', '\').ToUpper() + ':' }) | Where-Object { $_ -in $wszystkie } | Select-Object -Unique)
}
function OpisDysku($d) {
    $nazwa = if ($d.VolumeName) { $d.VolumeName } else { L 'bez nazwy' 'no label' }
    (L '{0} {1} - wolne {2} z {3}' '{0} {1} - {2} free of {3}') -f $d.DeviceID, $nazwa, (Rozmiar $d.FreeSpace), (Rozmiar $d.Size)
}

# Kosz uzytkownika na kazdym wybranym dysku: X:\$Recycle.Bin\<SID>
function FolderyKosza { foreach ($d in DyskiWybrane) { $p = "$($d.DeviceID)\`$Recycle.Bin\$UzytkownikSid"; if (Test-Path -LiteralPath $p) { $p } } }
