<#
    LLMCleaner - biala lista kategorii smieci
#>

# Rozmiar do pokazania (kategorie bez mierzalnego rozmiaru maja '-')
function MierzalnaKategoria($k) { $k.Typ -in 'folder', 'kosz', 'miniatury', 'winold', 'driverstore' -or ($k.Typ -in 'docker', 'dockerall' -and $k.Bajty -gt 0) }
function RozmiarKategorii($k) { if (MierzalnaKategoria $k) { Rozmiar $k.Bajty } else { '-' } }

function ProfilePrzegladarki($userData) {
    if (-not (Test-Path -LiteralPath $userData)) { return @() }
    Get-ChildItem -LiteralPath $userData -Directory -Force |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } |
        ForEach-Object { $_.FullName }
}

function CacheElectron($d) { "$d\Cache", "$d\Code Cache", "$d\GPUCache", "$d\DawnCache", "$d\Service Worker\CacheStorage" }

function ZbudujKategorie {
    $cachePrzegladarek = @()
    foreach ($ud in "$env:LOCALAPPDATA\Google\Chrome\User Data",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data") {
        foreach ($p in ProfilePrzegladarki $ud) {
            $cachePrzegladarek += "$p\Cache", "$p\Code Cache", "$p\GPUCache", "$p\Service Worker\CacheStorage"
        }
        $cachePrzegladarek += "$ud\GrShaderCache", "$ud\ShaderCache"
    }
    Get-ChildItem "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" -Directory -Force |
        ForEach-Object { $cachePrzegladarek += "$($_.FullName)\cache2" }

    # Cache aplikacji - kazda grupa jest pomijana osobno, gdy jej program dziala
    $steam = (Get-ItemProperty "$HKCU\Software\Valve\Steam").SteamPath
    $grupy = @(
        @{ Nazwa = 'Discord'; Procesy = @('discord'); Sciezki = @(CacheElectron "$env:APPDATA\discord") }
        @{ Nazwa = 'Slack'; Procesy = @('slack'); Sciezki = @(CacheElectron "$env:APPDATA\Slack") }
        @{ Nazwa = (L 'Teams (klasyczny)' 'Teams (classic)'); Procesy = @('teams'); Sciezki = @(CacheElectron "$env:APPDATA\Microsoft\Teams") }
        @{ Nazwa = 'VS Code'; Procesy = @('code'); Sciezki = @((CacheElectron "$env:APPDATA\Code") + "$env:APPDATA\Code\CachedData", "$env:APPDATA\Code\CachedExtensionVSIXs") }
        @{ Nazwa = 'Spotify'; Procesy = @('spotify'); Sciezki = @("$env:LOCALAPPDATA\Spotify\Data") }
        @{ Nazwa = 'Steam'; Procesy = @('steam', 'steamwebhelper')
            Sciezki = @($(if ($steam) { $s = $steam -replace '/', '\'; "$s\appcache\httpcache", "$s\appcache\librarycache" }) + "$env:LOCALAPPDATA\Steam\htmlcache")
        }
        @{ Nazwa = 'Epic Games Launcher'; Procesy = @('epicgameslauncher')
            Sciezki = @(Get-ChildItem "$env:LOCALAPPDATA\EpicGamesLauncher\Saved" -Directory -Force -Filter 'webcache*' | ForEach-Object { $_.FullName })
        }
        @{ Nazwa = 'Battle.net'; Procesy = @('battle.net'); Sciezki = @("$env:LOCALAPPDATA\Battle.net\BrowserCaches", "$env:LOCALAPPDATA\Battle.net\Cache") }
    )
    # Zostaja tylko aplikacje, ktore sa na tym komputerze
    foreach ($g in $grupy) { $g.Sciezki = @($g.Sciezki | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) }
    $grupy = @($grupy | Where-Object { $_.Sciezki.Count })
    # IDE JetBrains osobno: po usunieciu indeksow projekty indeksuja sie od nowa (kilka minut)
    $jetbrains = @{ Nazwa = 'JetBrains'; Procesy = @('phpstorm64', 'webstorm64', 'idea64', 'pycharm64', 'rider64', 'clion64', 'goland64', 'datagrip64', 'rubymine64', 'rustrover64')
        Sciezki = @(Get-ChildItem "$env:LOCALAPPDATA\JetBrains" -Directory -Force | ForEach-Object { "$($_.FullName)\caches", "$($_.FullName)\index" } | Where-Object { Test-Path -LiteralPath $_ })
    }
    $znalezione = if ($grupy) { ($grupy | ForEach-Object { $_.Nazwa }) -join ', ' } else { L 'brak' 'none' }

    $k = @(
        @{ Id = 'temp'; Nazwa = (L 'Pliki tymczasowe (TEMP)' 'Temporary files (TEMP)')
            Sciezki = @($env:TEMP, "$WinDir\Temp")
            Opis = (L 'Pliki tymczasowe programów i instalatorów. Pliki w użyciu są pomijane.' 'Temporary files of programs and installers. Files in use are skipped.')
        }
        @{ Id = 'inet'; Nazwa = (L 'Cache internetowy Windows (INetCache)' 'Windows internet cache (INetCache)')
            Sciezki = @("$env:LOCALAPPDATA\Microsoft\Windows\INetCache")
            Opis = (L 'Cache silnika WebView/IE. Odtwarza się sam.' 'WebView/IE engine cache. Rebuilds itself.')
        }
        @{ Id = 'kosz'; Nazwa = (L 'Kosz' 'Recycle Bin'); Typ = 'kosz'
            Opis = (L 'Pliki usunięte przez użytkownika. Po opróżnieniu nie da się ich przywrócić.' 'Files you deleted. They cannot be restored after emptying.')
        }
        @{ Id = 'wer'; Nazwa = (L 'Raporty błędów i zrzuty pamięci' 'Error reports and memory dumps')
            Sciezki = @("$env:LOCALAPPDATA\Microsoft\Windows\WER",
                "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
                "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
                "$env:LOCALAPPDATA\CrashDumps", "$WinDir\Minidump", "$WinDir\MEMORY.DMP", "$WinDir\LiveKernelReports")
            Opis = (L 'Raporty awarii programów, zrzuty pamięci po bluescreenach i raporty sterowników (LiveKernelReports, potrafią mieć kilka GB). Potrzebne tylko do diagnozy awarii.' 'Crash reports, blue screen memory dumps and driver reports (LiveKernelReports, can take several GB). Only needed to diagnose crashes.')
        }
        @{ Id = 'wu'; Nazwa = (L 'Cache Windows Update' 'Windows Update cache')
            Sciezki = @("$WinDir\SoftwareDistribution\Download", "$WinDir\SoftwareDistribution\DeliveryOptimization")
            Uslugi = @('wuauserv', 'bits')
            Opis = (L 'Pobrane już pliki aktualizacji. Windows pobierze je ponownie, jeśli będą potrzebne.' 'Already downloaded update files. Windows downloads them again if needed.')
        }
        @{ Id = 'logi'; Nazwa = (L 'Logi systemowe CBS/DISM (starsze niż 7 dni)' 'CBS/DISM system logs (older than 7 days)'); MinWiek = 7
            Sciezki = @("$WinDir\Logs\CBS", "$WinDir\Logs\DISM")
            Opis = (L 'Logi instalacji komponentów Windows.' 'Windows component installation logs.')
        }
        @{ Id = 'www'; Nazwa = (L 'Cache przeglądarek (Chrome, Edge, Brave, Firefox)' 'Browser caches (Chrome, Edge, Brave, Firefox)')
            Sciezki = $cachePrzegladarek
            Procesy = @('chrome', 'msedge', 'brave', 'firefox')
            Opis = (L 'Tylko cache stron i shaderów. Hasła, zakładki, historia i zalogowane sesje zostają.' 'Page and shader caches only. Passwords, bookmarks, history and sessions are kept.')
        }
        @{ Id = 'dev'; Nazwa = (L 'Cache narzędzi programistycznych' 'Developer tool caches')
            Sciezki = @("$env:LOCALAPPDATA\npm-cache", "$env:LOCALAPPDATA\pip\cache", "$env:LOCALAPPDATA\node-gyp\Cache",
                "$env:LOCALAPPDATA\Yarn\Cache", "$env:LOCALAPPDATA\uv\cache", "$env:LOCALAPPDATA\NuGet\v3-cache",
                "$env:LOCALAPPDATA\Composer\cache", "$env:LOCALAPPDATA\go-build",
                "$env:USERPROFILE\.gradle\caches", "$env:USERPROFILE\.cargo\registry\cache", "$env:USERPROFILE\.bun\install\cache")
            Opis = (L 'Pobrane paczki npm/pip/yarn/uv/NuGet/Composer/Gradle/Cargo/Bun i cache Go. Pobiorą się ponownie przy następnej instalacji lub budowaniu.' 'Downloaded npm/pip/yarn/uv/NuGet/Composer/Gradle/Cargo/Bun packages and the Go build cache. They are downloaded again on the next install or build.')
        }
        @{ Id = 'apki'; Nazwa = (L 'Cache aplikacji' 'App caches'); Grupy = $grupy
            Sciezki = @($grupy | ForEach-Object { $_.Sciezki })
            Opis = ((L 'Tylko cache, konta i ustawienia zostają. Uruchomione aplikacje są pomijane. Znalezione: {0}.' 'Cache only; accounts and settings are kept. Running apps are skipped. Found: {0}.') -f $znalezione)
        }
        @{ Id = 'ide'; Nazwa = (L 'Cache i indeksy IDE JetBrains' 'JetBrains IDE caches and indexes'); Grupy = @($jetbrains); Sciezki = $jetbrains.Sciezki; TylkoRecznie = $true
            Opis = (L 'Cache i indeksy PhpStorm, WebStorm, IntelliJ itd. (także starych wersji). Po czyszczeniu IDE indeksuje projekty od nowa. Pomijane, gdy IDE działa.' 'Caches and indexes of PhpStorm, WebStorm, IntelliJ etc. (old versions too). The IDE re-indexes projects afterwards. Skipped while the IDE is running.')
        }
        @{ Id = 'sterowniki'; Nazwa = (L 'Stare instalatory sterowników (NVIDIA, AMD)' 'Old driver installers (NVIDIA, AMD)')
            Sciezki = @("$Sys\NVIDIA", "$Sys\AMD", "$env:ProgramData\NVIDIA Corporation\Downloader")
            Opis = (L 'Rozpakowane i pobrane instalatory sterowników. Zainstalowany sterownik działa bez nich.' 'Extracted and downloaded driver installers. The installed driver works without them.')
        }
        @{ Id = 'shadery'; Nazwa = (L 'Cache shaderów GPU (NVIDIA, DirectX)' 'GPU shader caches (NVIDIA, DirectX)')
            Sciezki = @("$env:LOCALAPPDATA\NVIDIA\DXCache", "$env:LOCALAPPDATA\NVIDIA\GLCache", "$env:LOCALAPPDATA\D3DSCache")
            Opis = (L 'Skompilowane shadery. Pierwsze uruchomienie gier po czyszczeniu może się dłużej ładować.' 'Compiled shaders. Games may load longer the first time after cleaning.')
        }
        @{ Id = 'miniatury'; Nazwa = (L 'Miniaturki i cache ikon' 'Thumbnails and icon cache'); Typ = 'miniatury'
            Opis = (L 'Podglądy zdjęć i ikon w Eksploratorze. Wymaga restartu Eksploratora (pasek zadań zniknie na kilka sekund).' 'Picture and icon previews in File Explorer. Explorer restarts (the taskbar disappears for a few seconds).')
        }
        @{ Id = 'dns'; Nazwa = (L 'Cache DNS' 'DNS cache'); Typ = 'dns'
            Opis = (L 'Zapamiętane adresy stron. Nie zwalnia miejsca, pomaga przy problemach z siecią.' 'Remembered website addresses. Frees no space; helps with network problems.')
        }
        @{ Id = 'winold'; Nazwa = (L 'Poprzednia wersja Windows (Windows.old)' 'Previous Windows version (Windows.old)'); Typ = 'winold'; TylkoRecznie = $true
            Sciezki = @("$Sys\Windows.old", "$Sys\`$WINDOWS.~BT", "$Sys\`$WINDOWS.~WS")
            Opis = (L 'Kopia systemu sprzed dużej aktualizacji, zwykle 10-30 GB. Po usunięciu nie da się wrócić do poprzedniej wersji Windows.' 'A copy of the system from before a major update, usually 10-30 GB. Afterwards you cannot go back to the previous Windows version.')
        }
        @{ Id = 'dism'; Nazwa = (L 'Magazyn komponentów WinSxS (DISM)' 'WinSxS component store (DISM)'); Typ = 'dism'; TylkoRecznie = $true
            Opis = (L 'Usuwa zastąpione wersje komponentów Windows, zwykle 1-3 GB. Trwa kilka minut. Potem nie da się odinstalować wcześniejszych aktualizacji.' 'Removes superseded Windows components, usually 1-3 GB. Takes a few minutes. Older updates can no longer be uninstalled afterwards.')
        }
    )
    if (Get-Command Get-WindowsDriver) {
        $k += @{ Id = 'driverstore'; Nazwa = (L 'Starsze wersje sterowników (DriverStore)' 'Older driver versions (DriverStore)'); Typ = 'driverstore'; TylkoRecznie = $true
            Opis = (L 'Wersje sterowników zastąpione nowszymi, np. stare sterowniki karty graficznej (często 1-5 GB). Sterowniki używane i najnowsza wersja każdego zostają. Potem nie da się wrócić do starszej wersji w Menedżerze urządzeń.' 'Driver versions replaced by newer ones, e.g. old graphics drivers (often 1-5 GB). Drivers in use and the newest version of each are kept. Afterwards you cannot roll back to an older version in Device Manager.')
        }
    }
    if (Get-Command docker) {
        $k += @{ Id = 'dockerall'; Nazwa = (L 'Docker - wszystko (kontenery, obrazy, wolumeny)' 'Docker - everything (containers, images, volumes)'); Typ = 'dockerall'; TylkoRecznie = $true
            Opis = (L 'Zatrzymuje i usuwa WSZYSTKIE kontenery, także działające, a potem docker system prune -a --volumes: wszystkie obrazy, wolumeny (TAKŻE BAZY DANYCH w nich), sieci i cache budowania. Docker zostaje pusty. Docker musi być uruchomiony. Na Docker Desktop miejsce wraca na dysk po kompaktowaniu dysku WSL.' 'Stops and removes ALL containers, including running ones, then docker system prune -a --volumes: all images, volumes (INCLUDING DATABASES in them), networks and the build cache. Docker is left empty. Docker must be running. On Docker Desktop the space returns to the drive after the WSL disk is compacted.')
        }
        $k += @{ Id = 'docker'; Nazwa = (L 'Docker - cache budowania' 'Docker build cache'); Typ = 'docker'; TylkoRecznie = $true
            Opis = (L 'Tylko build cache. Obrazy, kontenery i wolumeny (w tym bazy danych) zostają.' 'Build cache only. Images, containers and volumes (including databases) are kept.')
        }
    }
    foreach ($x in $k) { if (-not $x.Typ) { $x.Typ = 'folder' } }
    $k
}

$sciezkaExplorer = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
function PlikiMiniatur {
    Get-ChildItem -LiteralPath $sciezkaExplorer -Force -File |
        Where-Object { $_.Name -like 'thumbcache_*.db' -or $_.Name -like 'iconcache_*.db' }
}

# Starsze wersje sterownikow w magazynie (DriverStore). Pakiety grupujemy po nazwie oryginalnego .inf,
# dostawcy i klasie; w grupie zostaje najnowsza wersja i kazda uzywana przez urzadzenie. Pozostale usuwa
# pnputil bez /force, wiec i tak odmowi pakietu w uzyciu. Tak samo dziala DriverStore Explorer.
function WersjaSterownika($v) { $x = $null; if ([version]::TryParse("$v", [ref]$x)) { $x } else { [version]'0.0' } }
function StareSterowniki {
    $uzywane = @{}
    foreach ($d in Get-CimInstance Win32_PnPSignedDriver) { if ($d.InfName) { $uzywane[$d.InfName.ToLower()] = 1 } }
    $grupy = @{}
    foreach ($d in Get-WindowsDriver -Online) {
        if (-not $d.Driver -or -not $d.OriginalFileName) { continue }
        $klucz = '{0}|{1}|{2}' -f (Split-Path $d.OriginalFileName -Leaf).ToLower(), $d.ProviderName, $d.ClassName
        if (-not $grupy[$klucz]) { $grupy[$klucz] = [System.Collections.Generic.List[object]]::new() }
        $grupy[$klucz].Add($d)
    }
    foreach ($g in $grupy.Values) {
        if ($g.Count -lt 2) { continue }
        $odNajnowszej = @($g | Sort-Object @{ Expression = { WersjaSterownika $_.Version }; Descending = $true }, @{ Expression = { $_.Date }; Descending = $true })
        foreach ($d in @($odNajnowszej | Select-Object -Skip 1)) {
            if ($uzywane[$d.Driver.ToLower()]) { continue }
            $folder = Split-Path $d.OriginalFileName -Parent
            # Zwykla suma: pliki magazynu naleza do systemu, test blokady uznalby je wszystkie za zablokowane
            @{ Inf = $d.Driver; Nazwa = (Split-Path $d.OriginalFileName -Leaf); Dostawca = $d.ProviderName; Wersja = $d.Version
                Folder = $folder; Bajty = [double](Pliki $folder | Measure-Object Length -Sum).Sum
            }
        }
    }
}
