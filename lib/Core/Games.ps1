<#
    LLMCleaner - leftovers of uninstalled Steam and Epic games
#>

function Get-SteamLibraries {
    $steam = (Get-ItemProperty "$HKCU\Software\Valve\Steam").SteamPath
    if (-not $steam) { return }
    $steam = $steam -replace '/', '\'
    $libraries = @($steam)
    $vdf = "$steam\steamapps\libraryfolders.vdf"
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) { $libraries += $m.Groups[1].Value -replace '\\\\', '\' }
    }
    $libraries | Sort-Object -Unique
}

# Nazwy zainstalowanych gier Steam (z manifestow) - zeby nie brac ich ustawien za pozostalosci
function Get-SteamGames {
    foreach ($b in Get-SteamLibraries) {
        foreach ($acf in Get-ChildItem -LiteralPath "$b\steamapps" -Filter 'appmanifest_*.acf') {
            $t = Get-Content -LiteralPath $acf.FullName -Raw
            foreach ($field in 'name', 'installdir') { $m = [regex]::Match($t, """$field""\s+""([^""]+)"""); if ($m.Success) { $m.Groups[1].Value } }
        }
    }
}

function Find-OrphanedSteamGames {
    foreach ($b in @(Get-SteamLibraries | Where-Object { Test-OnSelectedDrive $_ })) {
        $sa = "$b\steamapps"
        if (-not (Test-Path -LiteralPath $sa)) { continue }
        $dirs = @{}; $ids = @{}
        foreach ($acf in Get-ChildItem -LiteralPath $sa -Filter 'appmanifest_*.acf') {
            $t = Get-Content -LiteralPath $acf.FullName -Raw
            $m = [regex]::Match($t, '"installdir"\s+"([^"]+)"'); if ($m.Success) { $dirs[$m.Groups[1].Value.ToLower()] = 1 }
            $m = [regex]::Match($t, '"appid"\s+"(\d+)"'); if ($m.Success) { $ids[$m.Groups[1].Value] = 1 }
        }
        foreach ($d in Get-ChildItem -LiteralPath "$sa\common" -Directory -Force) {
            if (-not $dirs[$d.Name.ToLower()] -and -not (Test-SkippedName $d.Name)) {
                @{ Type = 'folder'; Path = $d.FullName; Name = $d.Name; Confidence = 'high'; Game = $true
                    Reason = (L 'Folder gry Steam bez manifestu - gra została odinstalowana, pliki zostały.' 'Steam game folder without a manifest - the game was uninstalled but its files remain.')
                }
            }
        }
        foreach ($sub in 'shadercache', 'workshop\content') {
            foreach ($d in Get-ChildItem -LiteralPath "$sa\$sub" -Directory -Force) {
                if ($d.Name -match '^\d+$' -and -not $ids[$d.Name]) {
                    @{ Type = 'folder'; Path = $d.FullName; Name = "Steam $sub $($d.Name)"; Confidence = 'high'; Game = $true
                        Reason = ((L 'Steam {0} dla gry (appid {1}), której już nie ma.' 'Steam {0} for a game (appid {1}) that is no longer installed.') -f $sub, $d.Name)
                    }
                }
            }
        }
    }
}

# Gra z Epic Games Launcher ma w swoim folderze podfolder .egstore. Folder nadrzedny gry (np. G:\ albo
# Program Files) NIE jest biblioteka Epic - stoja w nim zwykle inne programy i gry. Dlatego folder spoza
# folderu "Epic Games" trafia na liste tylko wtedy, gdy ma .egstore, a korzen dysku nigdy nie jest traktowany
# jak biblioteka (wczesniej regula proponowala do usuniecia cale G:\Steam czy P:\Git).
function Find-OrphanedEpicGames {
    $man = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
    if (-not (Test-Path -LiteralPath $man)) { return }
    $installed = @{}; $parents = @{ "$env:ProgramFiles\Epic Games".ToLower() = 1 }
    foreach ($i in Get-ChildItem -LiteralPath $man -Filter *.item) {
        try { $loc = (Get-Content -LiteralPath $i.FullName -Raw | ConvertFrom-Json).InstallLocation } catch { Add-ScanError "manifest Epic $($i.Name)" $_; continue }
        if (-not $loc) { continue }
        $loc = $loc.Replace('/', '\').TrimEnd('\').ToLower()
        $installed[$loc] = 1
        $r = Split-Path $loc -Parent
        if ($r) { $parents[$r] = 1 }   # korzen zostaje jako G:\ (samo G: to biezacy folder dysku)
    }
    $script:EpicInstalled = @($installed.Keys)
    foreach ($r in @($parents.Keys | Where-Object { Test-OnSelectedDrive $_ })) {
        $epicFolder = (Split-Path $r -Leaf) -like '*epic*'
        foreach ($d in Get-ChildItem -LiteralPath $r -Directory -Force) {
            if ($installed[$d.FullName.ToLower()] -or $d.Name -in 'Launcher', 'DirectXRedist' -or $d.Name -like 'UE_*') { continue }
            if ($d.Attributes -band $REPARSE -or $d.Attributes -band [IO.FileAttributes]::System -or (Test-ProtectedFolder $d.FullName)) { continue }
            $egstore = Test-Path -LiteralPath (Join-Path $d.FullName '.egstore')
            if (-not $egstore -and -not $epicFolder) { continue }
            @{ Type = 'folder'; Path = $d.FullName; Name = $d.Name; Game = $true
                Confidence = $(if ($egstore) { 'high' } else { 'medium' })
                Reason = (L 'Folder gry Epic, której nie ma na liście zainstalowanych w Epic Games Launcher.' 'Epic game folder that is not on the Epic Games Launcher list of installed games.')
            }
        }
    }
}
