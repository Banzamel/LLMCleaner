<#
    LLMCleaner - whitelist of junk categories
#>

# Size to display (categories without a measurable size show '-')
function Test-MeasurableCategory($k) { $k.Type -in 'folder', 'recyclebin', 'thumbnails', 'winold', 'driverstore' -or ($k.Type -in 'docker', 'dockerall' -and $k.Bytes -gt 0) }
function Format-CategorySize($k) { if (Test-MeasurableCategory $k) { Format-Size $k.Bytes } else { '-' } }

function Get-BrowserProfiles($userData) {
    if (-not (Test-Path -LiteralPath $userData)) { return @() }
    Get-ChildItem -LiteralPath $userData -Directory -Force |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } |
        ForEach-Object { $_.FullName }
}

function Get-ElectronCache($d) { "$d\Cache", "$d\Code Cache", "$d\GPUCache", "$d\DawnCache", "$d\Service Worker\CacheStorage" }

function New-Categories {
    $browserCache = @()
    foreach ($ud in "$env:LOCALAPPDATA\Google\Chrome\User Data",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data") {
        foreach ($p in Get-BrowserProfiles $ud) {
            $browserCache += "$p\Cache", "$p\Code Cache", "$p\GPUCache", "$p\Service Worker\CacheStorage"
        }
        $browserCache += "$ud\GrShaderCache", "$ud\ShaderCache"
    }
    Get-ChildItem "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" -Directory -Force |
        ForEach-Object { $browserCache += "$($_.FullName)\cache2" }

    # App caches - each group is skipped separately while its program is running
    $steam = (Get-ItemProperty "$HKCU\Software\Valve\Steam").SteamPath
    $groups = @(
        @{ Name = 'Discord'; Processes = @('discord'); Paths = @(Get-ElectronCache "$env:APPDATA\discord") }
        @{ Name = 'Slack'; Processes = @('slack'); Paths = @(Get-ElectronCache "$env:APPDATA\Slack") }
        @{ Name = (L 'Teams (klasyczny)' 'Teams (classic)'); Processes = @('teams'); Paths = @(Get-ElectronCache "$env:APPDATA\Microsoft\Teams") }
        @{ Name = 'VS Code'; Processes = @('code'); Paths = @((Get-ElectronCache "$env:APPDATA\Code") + "$env:APPDATA\Code\CachedData", "$env:APPDATA\Code\CachedExtensionVSIXs") }
        @{ Name = 'Spotify'; Processes = @('spotify'); Paths = @("$env:LOCALAPPDATA\Spotify\Data") }
        @{ Name = 'Steam'; Processes = @('steam', 'steamwebhelper')
            Paths = @($(if ($steam) { $s = $steam -replace '/', '\'; "$s\appcache\httpcache", "$s\appcache\librarycache" }) + "$env:LOCALAPPDATA\Steam\htmlcache")
        }
        @{ Name = 'Epic Games Launcher'; Processes = @('epicgameslauncher')
            Paths = @(Get-ChildItem "$env:LOCALAPPDATA\EpicGamesLauncher\Saved" -Directory -Force -Filter 'webcache*' | ForEach-Object { $_.FullName })
        }
        @{ Name = 'Battle.net'; Processes = @('battle.net'); Paths = @("$env:LOCALAPPDATA\Battle.net\BrowserCaches", "$env:LOCALAPPDATA\Battle.net\Cache") }
    )
    # Keep only apps present on this computer
    foreach ($g in $groups) { $g.Paths = @($g.Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) }
    $groups = @($groups | Where-Object { $_.Paths.Count })
    # JetBrains IDEs separately: after deleting indexes projects re-index (a few minutes)
    $jetbrains = @{ Name = 'JetBrains'; Processes = @('phpstorm64', 'webstorm64', 'idea64', 'pycharm64', 'rider64', 'clion64', 'goland64', 'datagrip64', 'rubymine64', 'rustrover64')
        Paths = @(Get-ChildItem "$env:LOCALAPPDATA\JetBrains" -Directory -Force | ForEach-Object { "$($_.FullName)\caches", "$($_.FullName)\index" } | Where-Object { Test-Path -LiteralPath $_ })
    }
    $found = if ($groups) { ($groups | ForEach-Object { $_.Name }) -join ', ' } else { L 'brak' 'none' }

    $k = @(
        @{ Id = 'temp'; Name = (L 'Pliki tymczasowe (TEMP)' 'Temporary files (TEMP)')
            Paths = @($env:TEMP, "$WinDir\Temp")
            Description = (L 'Pliki tymczasowe programów i instalatorów. Pliki w użyciu są pomijane.' 'Temporary files of programs and installers. Files in use are skipped.')
        }
        @{ Id = 'inet'; Name = (L 'Cache internetowy Windows (INetCache)' 'Windows internet cache (INetCache)')
            Paths = @("$env:LOCALAPPDATA\Microsoft\Windows\INetCache")
            Description = (L 'Cache silnika WebView/IE. Odtwarza się sam.' 'WebView/IE engine cache. Rebuilds itself.')
        }
        @{ Id = 'recyclebin'; Name = (L 'Kosz' 'Recycle Bin'); Type = 'recyclebin'
            Description = (L 'Pliki usunięte przez użytkownika. Po opróżnieniu nie da się ich przywrócić.' 'Files you deleted. They cannot be restored after emptying.')
        }
        @{ Id = 'wer'; Name = (L 'Raporty błędów i zrzuty pamięci' 'Error reports and memory dumps')
            Paths = @("$env:LOCALAPPDATA\Microsoft\Windows\WER",
                "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
                "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
                "$env:LOCALAPPDATA\CrashDumps", "$WinDir\Minidump", "$WinDir\MEMORY.DMP", "$WinDir\LiveKernelReports")
            Description = (L 'Raporty awarii programów, zrzuty pamięci po bluescreenach i raporty sterowników (LiveKernelReports, potrafią mieć kilka GB). Potrzebne tylko do diagnozy awarii.' 'Crash reports, blue screen memory dumps and driver reports (LiveKernelReports, can take several GB). Only needed to diagnose crashes.')
        }
        @{ Id = 'wu'; Name = (L 'Cache Windows Update' 'Windows Update cache')
            Paths = @("$WinDir\SoftwareDistribution\Download", "$WinDir\SoftwareDistribution\DeliveryOptimization")
            Services = @('wuauserv', 'bits')
            Description = (L 'Pobrane już pliki aktualizacji. Windows pobierze je ponownie, jeśli będą potrzebne.' 'Already downloaded update files. Windows downloads them again if needed.')
        }
        @{ Id = 'logs'; Name = (L 'Logi systemowe CBS/DISM (starsze niż 7 dni)' 'CBS/DISM system logs (older than 7 days)'); MinAge = 7
            Paths = @("$WinDir\Logs\CBS", "$WinDir\Logs\DISM")
            Description = (L 'Logi instalacji komponentów Windows.' 'Windows component installation logs.')
        }
        @{ Id = 'www'; Name = (L 'Cache przeglądarek (Chrome, Edge, Brave, Firefox)' 'Browser caches (Chrome, Edge, Brave, Firefox)')
            Paths = $browserCache
            Processes = @('chrome', 'msedge', 'brave', 'firefox')
            Description = (L 'Tylko cache stron i shaderów. Hasła, zakładki, historia i zalogowane sesje zostają.' 'Page and shader caches only. Passwords, bookmarks, history and sessions are kept.')
        }
        @{ Id = 'dev'; Name = (L 'Cache narzędzi programistycznych' 'Developer tool caches')
            Paths = @("$env:LOCALAPPDATA\npm-cache", "$env:LOCALAPPDATA\pip\cache", "$env:LOCALAPPDATA\node-gyp\Cache",
                "$env:LOCALAPPDATA\Yarn\Cache", "$env:LOCALAPPDATA\uv\cache", "$env:LOCALAPPDATA\NuGet\v3-cache",
                "$env:LOCALAPPDATA\Composer\cache", "$env:LOCALAPPDATA\go-build",
                "$env:USERPROFILE\.gradle\caches", "$env:USERPROFILE\.cargo\registry\cache", "$env:USERPROFILE\.bun\install\cache")
            Description = (L 'Pobrane paczki npm/pip/yarn/uv/NuGet/Composer/Gradle/Cargo/Bun i cache Go. Pobiorą się ponownie przy następnej instalacji lub budowaniu.' 'Downloaded npm/pip/yarn/uv/NuGet/Composer/Gradle/Cargo/Bun packages and the Go build cache. They are downloaded again on the next install or build.')
        }
        @{ Id = 'apps'; Name = (L 'Cache aplikacji' 'App caches'); Groups = $groups
            Paths = @($groups | ForEach-Object { $_.Paths })
            Description = ((L 'Tylko cache, konta i ustawienia zostają. Uruchomione aplikacje są pomijane. Znalezione: {0}.' 'Cache only; accounts and settings are kept. Running apps are skipped. Found: {0}.') -f $found)
        }
        @{ Id = 'ide'; Name = (L 'Cache i indeksy IDE JetBrains' 'JetBrains IDE caches and indexes'); Groups = @($jetbrains); Paths = $jetbrains.Paths; OptIn = $true
            Description = (L 'Cache i indeksy PhpStorm, WebStorm, IntelliJ itd. (także starych wersji). Po czyszczeniu IDE indeksuje projekty od nowa. Pomijane, gdy IDE działa.' 'Caches and indexes of PhpStorm, WebStorm, IntelliJ etc. (old versions too). The IDE re-indexes projects afterwards. Skipped while the IDE is running.')
        }
        @{ Id = 'drivers'; Name = (L 'Stare instalatory sterowników (NVIDIA, AMD)' 'Old driver installers (NVIDIA, AMD)')
            Paths = @("$Sys\NVIDIA", "$Sys\AMD", "$env:ProgramData\NVIDIA Corporation\Downloader")
            Description = (L 'Rozpakowane i pobrane instalatory sterowników. Zainstalowany sterownik działa bez nich.' 'Extracted and downloaded driver installers. The installed driver works without them.')
        }
        @{ Id = 'shaders'; Name = (L 'Cache shaderów GPU (NVIDIA, DirectX)' 'GPU shader caches (NVIDIA, DirectX)')
            Paths = @("$env:LOCALAPPDATA\NVIDIA\DXCache", "$env:LOCALAPPDATA\NVIDIA\GLCache", "$env:LOCALAPPDATA\D3DSCache")
            Description = (L 'Skompilowane shadery. Pierwsze uruchomienie gier po czyszczeniu może się dłużej ładować.' 'Compiled shaders. Games may load longer the first time after cleaning.')
        }
        @{ Id = 'thumbnails'; Name = (L 'Miniaturki i cache ikon' 'Thumbnails and icon cache'); Type = 'thumbnails'
            Description = (L 'Podglądy zdjęć i ikon w Eksploratorze. Wymaga restartu Eksploratora (pasek zadań zniknie na kilka sekund).' 'Picture and icon previews in File Explorer. Explorer restarts (the taskbar disappears for a few seconds).')
        }
        @{ Id = 'dns'; Name = (L 'Cache DNS' 'DNS cache'); Type = 'dns'
            Description = (L 'Zapamiętane adresy stron. Nie zwalnia miejsca, pomaga przy problemach z siecią.' 'Remembered website addresses. Frees no space; helps with network problems.')
        }
        @{ Id = 'winold'; Name = (L 'Poprzednia wersja Windows (Windows.old)' 'Previous Windows version (Windows.old)'); Type = 'winold'; OptIn = $true
            Paths = @("$Sys\Windows.old", "$Sys\`$WINDOWS.~BT", "$Sys\`$WINDOWS.~WS")
            Description = (L 'Kopia systemu sprzed dużej aktualizacji, zwykle 10-30 GB. Po usunięciu nie da się wrócić do poprzedniej wersji Windows.' 'A copy of the system from before a major update, usually 10-30 GB. Afterwards you cannot go back to the previous Windows version.')
        }
        @{ Id = 'dism'; Name = (L 'Magazyn komponentów WinSxS (DISM)' 'WinSxS component store (DISM)'); Type = 'dism'; OptIn = $true
            Description = (L 'Usuwa zastąpione wersje komponentów Windows, zwykle 1-3 GB. Trwa kilka minut. Potem nie da się odinstalować wcześniejszych aktualizacji.' 'Removes superseded Windows components, usually 1-3 GB. Takes a few minutes. Older updates can no longer be uninstalled afterwards.')
        }
    )
    if (Get-Command Get-WindowsDriver) {
        $k += @{ Id = 'driverstore'; Name = (L 'Starsze wersje sterowników (DriverStore)' 'Older driver versions (DriverStore)'); Type = 'driverstore'; OptIn = $true
            Description = (L 'Wersje sterowników zastąpione nowszymi, np. stare sterowniki karty graficznej (często 1-5 GB). Sterowniki używane i najnowsza wersja każdego zostają. Potem nie da się wrócić do starszej wersji w Menedżerze urządzeń.' 'Driver versions replaced by newer ones, e.g. old graphics drivers (often 1-5 GB). Drivers in use and the newest version of each are kept. Afterwards you cannot roll back to an older version in Device Manager.')
        }
    }
    if (Get-Command docker) {
        $k += @{ Id = 'dockerall'; Name = (L 'Docker - wszystko (kontenery, obrazy, wolumeny)' 'Docker - everything (containers, images, volumes)'); Type = 'dockerall'; OptIn = $true
            Description = (L 'Zatrzymuje i usuwa WSZYSTKIE kontenery, także działające, a potem docker system prune -a --volumes: wszystkie obrazy, wolumeny (TAKŻE BAZY DANYCH w nich), sieci i cache budowania. Docker zostaje pusty. Docker musi być uruchomiony. Na Docker Desktop miejsce wraca na dysk po kompaktowaniu dysku WSL.' 'Stops and removes ALL containers, including running ones, then docker system prune -a --volumes: all images, volumes (INCLUDING DATABASES in them), networks and the build cache. Docker is left empty. Docker must be running. On Docker Desktop the space returns to the drive after the WSL disk is compacted.')
        }
        $k += @{ Id = 'docker'; Name = (L 'Docker - cache budowania' 'Docker build cache'); Type = 'docker'; OptIn = $true
            Description = (L 'Tylko build cache. Obrazy, kontenery i wolumeny (w tym bazy danych) zostają.' 'Build cache only. Images, containers and volumes (including databases) are kept.')
        }
    }
    foreach ($x in $k) { if (-not $x.Type) { $x.Type = 'folder' } }
    $k
}

$explorerPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
function Get-ThumbnailFiles {
    Get-ChildItem -LiteralPath $explorerPath -Force -File |
        Where-Object { $_.Name -like 'thumbcache_*.db' -or $_.Name -like 'iconcache_*.db' }
}

# Older driver versions in the DriverStore. Packages are grouped by original .inf name,
# provider and class; each group keeps the newest version and any used by a device. The rest are removed
# by pnputil without /force, so it refuses a package in use anyway. DriverStore Explorer works the same way.
function ConvertTo-DriverVersion($v) { $x = $null; if ([version]::TryParse("$v", [ref]$x)) { $x } else { [version]'0.0' } }
function Get-OldDrivers {
    $used = @{}
    foreach ($d in Get-CimInstance Win32_PnPSignedDriver) { if ($d.InfName) { $used[$d.InfName.ToLower()] = 1 } }
    $groups = @{}
    foreach ($d in Get-WindowsDriver -Online) {
        if (-not $d.Driver -or -not $d.OriginalFileName) { continue }
        $key = '{0}|{1}|{2}' -f (Split-Path $d.OriginalFileName -Leaf).ToLower(), $d.ProviderName, $d.ClassName
        if (-not $groups[$key]) { $groups[$key] = [System.Collections.Generic.List[object]]::new() }
        $groups[$key].Add($d)
    }
    foreach ($g in $groups.Values) {
        if ($g.Count -lt 2) { continue }
        $newestFirst = @($g | Sort-Object @{ Expression = { ConvertTo-DriverVersion $_.Version }; Descending = $true }, @{ Expression = { $_.Date }; Descending = $true })
        foreach ($d in @($newestFirst | Select-Object -Skip 1)) {
            if ($used[$d.Driver.ToLower()]) { continue }
            $folder = Split-Path $d.OriginalFileName -Parent
            # Plain sum: store files belong to the system, the lock test would treat them all as locked
            @{ Inf = $d.Driver; Name = (Split-Path $d.OriginalFileName -Leaf); Provider = $d.ProviderName; Version = $d.Version
                Folder = $folder; Bytes = [double](Get-AllFiles $folder | Measure-Object Length -Sum).Sum
            }
        }
    }
}
