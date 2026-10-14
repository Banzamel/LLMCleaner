<#
    LLMCleaner - aktualizacje programu z GitHuba
#>

# Jedno zapytanie do GitHuba przy starcie (bez danych o komputerze); wylacza je -BezAktualizacji.
$Repo = 'Banzamel/LLMCleaner'
$script:Aktualizacja = $null

function SprawdzAktualizacje {
    try {
        $r = CzekajNa {
            param($url, $ua)
            Invoke-RestMethod $url -TimeoutSec 4 -ErrorAction Stop -Headers @{ 'User-Agent' = $ua }
        } @("https://api.github.com/repos/$Repo/releases/latest", "LLMCleaner/$Wersja")
        $nowa = [version]($r.tag_name.TrimStart('v'))
        if ($nowa -le [version]$Wersja) { return }
        $setup = $r.assets | Where-Object { $_.name -like 'LLMCleaner-Setup-*.exe' } | Select-Object -First 1
        $script:Aktualizacja = @{ Wersja = "$nowa"; Strona = $r.html_url; Instalator = $setup.browser_download_url; Nazwa = $setup.name }
        Log "Dostepna aktualizacja: $nowa"
    }
    catch { Log "Sprawdzanie aktualizacji: $($_.Exception.Message)" }
}

# Pobiera instalator i uruchamia go jako zwykly uzytkownik (przez Eksplorator), zeby
# aktualizacja trafila w ten sam tryb instalacji co poprzednio. Zwraca $true, gdy wystartowal.
function ZainstalujAktualizacje {
    $a = $script:Aktualizacja
    $zainstalowany = Test-Path -LiteralPath (Join-Path $AppDir 'unins000.exe')
    if (-not $zainstalowany -or -not $a.Instalator) {
        Wypisz ((L '   Wersja portable - pobierz nową wersję ze strony: {0}' '   Portable version - download the new version from: {0}') -f $a.Strona) 'Yellow'
        return $false
    }
    $plik = Join-Path $env:TEMP $a.Nazwa
    Wypisz ((L '   Pobieram {0}...' '   Downloading {0}...') -f $a.Nazwa) 'Gray'
    try {
        CzekajNa {
            param($url, $plik)
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest $url -OutFile $plik -UseBasicParsing -ErrorAction Stop
        } @($a.Instalator, $plik) | Out-Null
    }
    catch { Wypisz ((L '   Nie udało się pobrać: {0}' '   Download failed: {0}') -f $_.Exception.Message) 'Yellow'; return $false }
    Log "Aktualizacja: uruchamiam $plik"
    Start-Process explorer.exe -ArgumentList "`"$plik`""
    $true
}
