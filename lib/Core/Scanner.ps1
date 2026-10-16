<#
    LLMCleaner - skan kategorii i dysku, Docker, caly skan
#>

function Measure-Categories {
    foreach ($k in $script:Categories) {
        Write-Line ("   {0}..." -f $k.Name) 'DarkGray'
        $k.Blocker = $null; $k.Note = $null
        $k.Bytes = 0.0; $k.Locked = 0.0
        try {
            switch ($k.Type) {
                'folder' {
                    $m = Measure-Paths $k.Paths ([int]$k.MinAge); $k.Bytes = $m.Bytes; $k.Files = $m.Files; $k.Locked = $m.InUse
                    if ($m.InUse) {
                        $largest = @($m.InUseFiles | Sort-Object Length -Descending)
                        $names = ($largest | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', '
                        if ($largest.Count -gt 3) { $names += (L ' i {0} innych' ' and {0} more') -f ($largest.Count - 3) }
                        $k.Note = (L 'Razem {0}: do usunięcia {1}, zablokowane {2} - pliki używane przez działające programy ({3}). Zamknij je, żeby usunąć resztę.' 'Total {0}: {1} can be deleted, {2} is locked - files used by running programs ({3}). Close them to delete the rest.') -f (Format-Size ($m.Bytes + $m.InUse)), (Format-Size $m.Bytes), (Format-Size $m.InUse), $names
                        Write-Log "$($k.Id): zablokowane $(Format-Size $m.InUse) w $($largest.Count) plikach, najwieksze: $names"
                    }
                }
                'winold' { $m = Measure-Paths $k.Paths; $k.Bytes = $m.Bytes; $k.Files = $m.Files }
                'recyclebin' { $k.Bytes = (Measure-Paths @(Get-RecycleBinFolders)).Bytes }
                'thumbnails' { $k.Bytes = [double](Get-ThumbnailFiles | Measure-Object Length -Sum).Sum }
                'docker' { $k.Bytes = [double](Get-DockerUsage).Cache; if (-not $script:DockerRunning) { $k.Note = L 'Docker nie działa - uruchom go, żeby zmierzyć i wyczyścić.' 'Docker is not running - start it to measure and clean.' } }
                'dockerall' {
                    $d = Get-DockerUsage
                    $k.Bytes = [double]$d.InUse
                    if (-not $script:DockerRunning) { $k.Note = L 'Docker nie działa - uruchom go, żeby zmierzyć i wyczyścić.' 'Docker is not running - start it to measure and clean.' }
                    elseif ($d.InUse -gt 0) { $k.Note = (L 'Zajęte: obrazy {0}, kontenery {1}, wolumeny {2}, cache budowania {3}. W tym nieużywane: {4}.' 'Used: images {0}, containers {1}, volumes {2}, build cache {3}. Unused part: {4}.') -f (Format-Size $d.UsedParts.Images), (Format-Size $d.UsedParts.Containers), (Format-Size $d.UsedParts.Volumes), (Format-Size $d.UsedParts.Cache), (Format-Size $d.ReclaimableTotal) }
                }
                'driverstore' {
                    $k.Packages = @(Get-OldDrivers | Sort-Object { $_.Bytes } -Descending)
                    $k.Bytes = [double]($k.Packages | ForEach-Object { $_.Bytes } | Measure-Object -Sum).Sum; $k.Files = $k.Packages.Count
                    if ($k.Packages.Count) {
                        $k.Note = (L 'Do usunięcia {0} pakietów, największe: {1}.' '{0} packages to remove, the largest: {1}.') -f $k.Packages.Count,
                            (($k.Packages | Select-Object -First 3 | ForEach-Object { '{0} {1} ({2}, {3})' -f $_.Name, $_.Version, $_.Provider, (Format-Size $_.Bytes) }) -join ', ')
                        Write-Log "driverstore: $(($k.Packages | ForEach-Object { "$($_.Inf)=$($_.Name) $($_.Version)" }) -join ', ')"
                    }
                }
            }
        }
        catch { Add-ScanError "kategoria $($k.Id)" $_ }
        if ($k.Processes -and (Get-Process $k.Processes)) { $k.Blocker = L 'uruchomiona przeglądarka - zamknij ją przed czyszczeniem' 'a browser is running - close it before cleaning' }
    }
}

# Docker: ile da sie odzyskac wedlug "docker system df" (kolumna RECLAIMABLE). Pusto, gdy Docker nie dziala.
$script:DockerRunning = $false
function ConvertFrom-DockerSize([string]$s) {
    $m = [regex]::Match("$s", '^\s*([\d\.]+)\s*([kKMGT]?)B')
    if (-not $m.Success) { return 0.0 }
    $mult = @{ '' = 1.0; 'k' = 1e3; 'M' = 1e6; 'G' = 1e9; 'T' = 1e12 }[$m.Groups[2].Value]   # klucze bez rozroznienia wielkosci liter
    [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) * $mult
}
function Get-DockerUsage {
    $w = @{ Images = 0.0; Containers = 0.0; Volumes = 0.0; Cache = 0.0; ReclaimableTotal = 0.0; InUse = 0.0; UsedParts = @{ Images = 0.0; Containers = 0.0; Volumes = 0.0; Cache = 0.0 } }
    $lines = @(docker system df --format '{{json .}}' 2>$null)
    $script:DockerRunning = $LASTEXITCODE -eq 0 -and $lines.Count
    foreach ($l in $lines) {
        try {
            $o = $l | ConvertFrom-Json -ErrorAction Stop
            $b = ConvertFrom-DockerSize $o.Reclaimable
            $z = ConvertFrom-DockerSize $o.Size
            $w.InUse += $z
            $t = switch -Wildcard ($o.Type) { 'Images' { 'Images' } 'Containers' { 'Containers' } '*Volumes' { 'Volumes' } 'Build Cache' { 'Cache' } }
            if ($t) { $w[$t] = $b; $w.UsedParts[$t] = $z }
        }
        catch { }
    }
    $w.ReclaimableTotal = $w.Images + $w.Containers + $w.Volumes + $w.Cache
    $w
}

function Get-DownloadsFolder { Get-UserShellFolder '{374DE290-123F-4565-9164-39C4925E467B}' "$env:USERPROFILE\Downloads" }

function Invoke-ProfileScan {
    $profileDir = $env:USERPROFILE
    $topFolders = @{}; $appdata = @{}
    $large = [System.Collections.Generic.List[object]]::new()
    $n = 0

    foreach ($f in Get-AllFiles $profileDir) {
        $n++
        if ($n % 5000 -eq 0) { Write-Status ((L '   przejrzano {0:N0} plików...' '   scanned {0:N0} files...') -f $n) }
        if ([int]$f.Attributes -band 0x401000) { continue }   # pliki tylko w chmurze (OneDrive)
        $parts = $f.FullName.Substring($profileDir.Length + 1).Split('\')
        if ($parts.Count -lt 2) { continue }
        $topFolders[$parts[0]] += $f.Length
        if ($parts[0] -eq 'AppData') {
            if ($parts.Count -gt 3 -and $parts[1] -in 'Local', 'Roaming') { $appdata["AppData\$($parts[1])\$($parts[2])"] += $f.Length }
        }
        elseif ($f.Length -ge 1GB) { $large.Add($f) }
    }
    Complete-Status ((L '   przejrzano {0:N0} plików w profilu.           ' '   scanned {0:N0} files in the profile.           ') -f $n)

    # Kandydaci do recznego usuniecia: duze pliki w Pobranych + pliki > 1 GB poza AppData.
    $downloads = Get-DownloadsFolder
    $candidates = @()
    $fromDownloads = @(Get-AllFiles $downloads | Where-Object { $_.Length -ge 100MB } | Sort-Object Length -Descending | Select-Object -First 15)
    $rest = @($large | Where-Object { $_.FullName -notlike "$downloads\*" } | Sort-Object Length -Descending | Select-Object -First 12)
    foreach ($f in @($fromDownloads) + @($rest)) {
        $candidates += @{ Path = $f.FullName; Bytes = [double]$f.Length; Modified = $f.LastWriteTime
            InDownloads = ($f.FullName -like "$downloads\*")
        }
    }

    $programs = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    "$HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" |
        Where-Object { $_.DisplayName -and ($_.EstimatedSize -as [double]) } |
        Sort-Object { $_.EstimatedSize -as [double] } -Descending | Select-Object -First 12 |
        ForEach-Object { @{ name = $_.DisplayName; size = (Format-Size (($_.EstimatedSize -as [double]) * 1KB)); installed = $_.InstallDate } }

    $hib = Get-Item -LiteralPath "$Sys\hiberfil.sys" -Force
    @{
        Candidates = $candidates
        Profile    = @($topFolders.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10 |
                ForEach-Object { @{ folder = $_.Key; size = (Format-Size $_.Value) } })
        AppData   = @($appdata.GetEnumerator() | Where-Object { $_.Value -ge 300MB } | Sort-Object Value -Descending |
                Select-Object -First 12 | ForEach-Object { @{ folder = $_.Key; size = (Format-Size $_.Value) } })
        Programs  = @($programs)
        System    = @{
            hiberfil            = $(if ($hib) { Format-Size $hib.Length } else { L 'brak (hibernacja wyłączona)' 'none (hibernation off)' })
            windows_old         = (Test-Path -LiteralPath "$Sys\Windows.old")
            old_setup_bt = (Test-Path -LiteralPath "$Sys\`$WINDOWS.~BT")
        }
        Drives     = @(Get-SelectedDrives | ForEach-Object { @{ drive = $_.DeviceID; free = (Format-Size $_.FreeSpace); total = (Format-Size $_.Size) } })
    }
}

# Caly skan: kategorie, profil, pozostalosci i plan. Wynik w $script:Kategorie/Pozostalosci/Dysk.
function Invoke-FullScan {
    Write-Log "Dyski: $($script:SelectedDrives -join ', '), uzytkownik: $UserSid$(if ($OtherUser) { ' (inne konto niz administrator)' })"
    $script:ScanErrors = 0
    $script:FreeBefore = Get-SystemFreeSpace
    try { $script:Categories = @(New-Categories) } catch { Add-ScanError 'kategorie' $_; $script:Categories = @() }
    Measure-Categories
    Write-Line (L '   Przeglądam profil użytkownika (duże pliki, AppData)...' '   Scanning the user profile (large files, AppData)...') 'DarkGray'
    try { $script:ProfileScan = Invoke-ProfileScan }
    catch { Add-ScanError 'profil' $_; $script:ProfileScan = @{ Candidates = @(); Profile = @(); AppData = @(); Programs = @(); System = @{}; Drives = @() } }
    Write-Line (L '   Szukam pozostałości po odinstalowanych programach i grach...' '   Looking for leftovers of uninstalled programs and games...') 'DarkGray'
    try { $leftoverList = @(Find-Leftovers) } catch { Add-ScanError 'pozostalosci' $_; $leftoverList = @() }
    # Duze pliki z Pobranych i spoza AppData - do decyzji uzytkownika, nigdy zaznaczone z gory
    foreach ($c in $script:ProfileScan.Candidates) {
        $leftoverList += @{ Type = 'file'; Path = $c.Path; Name = (Split-Path $c.Path -Leaf); Bytes = $c.Bytes
            LastWrite = $c.Modified; Confidence = 'low'
            Reason = $(if ($c.InDownloads) { L 'Duży plik w Pobranych - stary instalator albo archiwum?' 'Large file in Downloads - an old installer or archive?' }
                else { L 'Duży plik (ponad 1 GB) w profilu użytkownika.' 'Large file (over 1 GB) in the user profile.' })
        }
    }
    $n = 0; foreach ($p in $leftoverList) { $n++; $p.Id = "R$n" }
    $script:Leftovers = $leftoverList
    Complete-Status ((L '   Znaleziono pozostałości: {0} folderów, {1} plików, {2} wpisów rejestru, {3} zadań.' '   Leftovers found: {0} folders, {1} files, {2} registry entries, {3} tasks.') -f
        @($leftoverList | Where-Object { $_.Type -eq 'folder' }).Count, @($leftoverList | Where-Object { $_.Type -eq 'file' }).Count,
        @($leftoverList | Where-Object { $_.Type -in 'registry', 'regvalue' }).Count, @($leftoverList | Where-Object { $_.Type -eq 'task' }).Count)
    if ($script:ScanErrors) {
        Write-Line ((L '   Pominięto elementy, których nie dało się odczytać: {0} (szczegóły w logu: {1})' '   Skipped items that could not be read: {0} (details in the log: {1})') -f $script:ScanErrors, $LogFile) 'Yellow'
    }
    Build-Plan
    Write-Log "Raport: $(Get-ReportJson)"
}
