<#
    LLMCleaner - protected folders and the main leftover scan
#>

# Folder, ktorego nigdy nie proponujemy do usuniecia, bez wzgledu na to, co znalazla regula: korzen dysku,
# foldery systemowe w korzeniu (Kosz, System Volume Information...), foldery Windows, profilu i samego LLMCleanera
$RootSystemFolders = @('$recycle.bin', 'system volume information', 'recovery', 'config.msi', 'msocache', 'perflogs',
    'boot', 'windows', 'windows.old', 'program files', 'program files (x86)', 'programdata', 'users', 'documents and settings',
    'onedrivetemp', 'intel', 'amd', 'nvidia', 'drivers', 'efi')
function Test-ProtectedFolder([string]$path) {
    if (-not $path) { return $true }
    $s = $path.Trim().TrimEnd('\').ToLower()
    if ($s -notmatch '^[a-z]:\\.') { return $true }                      # korzen dysku albo dziwna sciezka
    $parts = $s -split '\\'
    if ($parts.Count -eq 2 -and ($parts[1] -in $RootSystemFolders -or $parts[1].StartsWith('$'))) { return $true }
    foreach ($c in $WinDir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:USERPROFILE, $env:APPDATA,
        $env:LOCALAPPDATA, "$env:USERPROFILE\AppData\LocalLow", (Split-Path $env:USERPROFILE -Parent), $AppDir) {
        if (-not $c) { continue }
        $c = $c.TrimEnd('\').ToLower()
        # Sam folder chroniony albo jego folder nadrzedny (np. P:\LLMCleaner, gdy program stoi w P:\LLMCleaner\app)
        if ($c -eq $s -or $c.StartsWith("$s\")) { return $true }
    }
    $false
}

# Folder zawiera zainstalowany program, biblioteke Steam albo gre Epic (np. G:\Steam, P:\Git) - wtedy nie jest pozostaloscia
function Test-ContainsInstalled([string]$path, $installed, $protectedPaths) {
    $s = $path.TrimEnd('\').ToLower()
    foreach ($p in @($installed.Paths) + @($protectedPaths)) {
        if (-not $p) { continue }
        $p = "$p".TrimEnd('\').ToLower()
        if ($p -eq $s -or $p.StartsWith("$s\")) { return $true }
    }
    $false
}

function Find-Leftovers {
    $script:EpicInstalled = @()
    $entries = @(Get-UninstallKeys)
    $dead = @(Find-DeadUninstallEntries $entries)
    $deadKeys = @($dead | ForEach-Object { $_.Path })
    $installed = Get-InstalledPrograms @($entries | Where-Object { $_.RegKey -notin $deadKeys })
    $now = Get-Date
    $results = [System.Collections.Generic.List[object]]::new()

    # Foldery programow
    $roots = @(
        @{ P = $env:APPDATA; Game = $false }, @{ P = $env:LOCALAPPDATA; Game = $false },
        @{ P = "$env:LOCALAPPDATA\Programs"; Game = $false }, @{ P = "$env:USERPROFILE\AppData\LocalLow"; Game = $false },
        @{ P = $env:ProgramData; Game = $false }, @{ P = $env:ProgramFiles; Game = $false }, @{ P = ${env:ProgramFiles(x86)}; Game = $false },
        @{ P = "$(Get-UserShellFolder 'Personal' "$env:USERPROFILE\Documents")\My Games"; Game = $true }
        @{ P = (Get-UserShellFolder '{4C5C32FF-BB9D-43b0-B5B4-2D72E54EAAA4}' "$env:USERPROFILE\Saved Games"); Game = $true })
    $allNames = [System.Collections.Generic.HashSet[string]]::new()
    $toCheck = @()
    foreach ($k in $roots) {
        foreach ($d in Get-ChildItem -LiteralPath $k.P -Directory -Force) {
            try {
                [void]$allNames.Add((ConvertTo-PlainName $d.Name))
                if ($d.Attributes -band $REPARSE -or $d.Attributes -band [IO.FileAttributes]::System) { continue }
                if ((Test-SkippedName $d.Name) -or (Test-ProtectedFolder $d.FullName)) { continue }
                if (Test-BelongsToProgram $d.Name $d.FullName $installed) { continue }
                $toCheck += @{ D = $d; Saves = $k.Game }
            }
            catch { Add-ScanError "folder $($d.FullName)" $_ }
        }
    }
    foreach ($c in $toCheck) {
        try {
            Write-Status ("   {0}" -f $c.D.FullName)
            $m = Measure-Folder $c.D.FullName
            $days = ($now - $m.LastWrite).TotalDays
            if ($days -lt 30) { continue }   # cos tam jeszcze pisze
            $results.Add(@{ Type = 'folder'; Path = $c.D.FullName; Name = $c.D.Name; Bytes = $m.Bytes; LastWrite = $m.LastWrite
                    # Odinstalowany program zwykle zostawia ustawienia i logi, nie pliki .exe - folder z .exe moze byc
                    # programem przenosnym bez wpisu w rejestrze, wiec nie zaznaczamy go z gory
                    Confidence = $(if ($c.Saves -or $m.HasExe) { 'low' } elseif ($days -ge 180) { 'high' } else { 'medium' })
                    Reason = $(if ($c.Saves) { L 'Zapisy/ustawienia gry - może chcesz je zachować.' 'Game saves/settings - you may want to keep them.' }
                        elseif ($m.HasExe) { L 'Brak zainstalowanego programu o tej nazwie, ale folder zawiera pliki .exe - może to program przenośny.' 'No installed program with this name, but the folder contains .exe files - it may be a portable program.' }
                        else { L 'Brak zainstalowanego programu o tej nazwie.' 'No installed program with this name.' })
                })
        }
        catch { Add-ScanError "folder $($c.D.FullName)" $_ }
    }

    # Gry
    $games = @()
    try { $games += @(Find-OrphanedSteamGames) } catch { Add-ScanError 'Steam' $_ }
    try { $games += @(Find-OrphanedEpicGames) } catch { Add-ScanError 'Epic' $_ }
    # Bezpiecznik: folder gry nie moze zawierac zainstalowanego programu, biblioteki Steam ani gry Epic
    $protectedPaths = @(Get-SteamLibraries) + @($script:EpicInstalled)
    foreach ($g in $games) {
        if ((Test-ProtectedFolder $g.Path) -or (Test-ContainsInstalled $g.Path $installed $protectedPaths)) { Write-Log "Pominieto chroniony folder gry: $($g.Path)"; continue }
        try { $m = Measure-Folder $g.Path; $g.Bytes = $m.Bytes; $g.LastWrite = $m.LastWrite; $results.Add($g) }
        catch { Add-ScanError "gra $($g.Path)" $_ }
    }

    # Rejestr: klucze producentow bez programu i bez folderu o tej nazwie
    $vendorKeys = [System.Collections.Generic.List[object]]::new()
    foreach ($r in "$HKCUName\Software", 'HKEY_LOCAL_MACHINE\SOFTWARE', 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node') {
        foreach ($k in Get-ChildItem "Registry::$r") {
            try {
                $n = $k.PSChildName
                if (Test-SkippedName $n) { continue }
                if (Test-BelongsToProgram $n $null $installed) { continue }
                if ($allNames.Contains((ConvertTo-PlainName $n))) { continue }
                # Klucz studia (np. Klei) moze nalezec do wciaz zainstalowanej gry (Klei\Don't Starve)
                $subkeys = @(Get-ChildItem -LiteralPath $k.PSPath | ForEach-Object { $_.PSChildName })
                if ($subkeys | Where-Object { (Test-BelongsToProgram $_ $null $installed) -or $allNames.Contains((ConvertTo-PlainName $_)) }) { continue }
                $contains = @($subkeys | Select-Object -First 3)
                $reason = L 'Klucz producenta bez zainstalowanego programu i folderu.' 'Vendor key with no installed program or folder.'
                if ($contains) { $reason += ((L ' Zawiera: {0}.' ' Contains: {0}.') -f ($contains -join ', ')) }
                $vendorKeys.Add(@{ Type = 'registry'; Path = "$r\$n"; Name = $n; Bytes = 0.0; Confidence = 'medium'; Subkeys = $contains; Reason = $reason })
            }
            catch { Add-ScanError "klucz $r\$($k.PSChildName)" $_ }
        }
    }

    $start = @()
    try { $start = @(Find-DeadStartupEntries) } catch { Add-ScanError 'startup' $_ }

    @($results | Sort-Object { $_.Bytes } -Descending) + @($dead) + @($start) + @($vendorKeys)
}
