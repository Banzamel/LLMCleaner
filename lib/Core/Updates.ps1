<#
    LLMCleaner - aktualizacje programu z GitHuba
#>

# Jedno zapytanie do GitHuba przy starcie (bez danych o komputerze); wylacza je -BezAktualizacji.
$Repo = 'Banzamel/LLMCleaner'
$script:AppUpdate = $null

function Find-AppUpdate {
    try {
        $r = Invoke-Background {
            param($url, $ua)
            Invoke-RestMethod $url -TimeoutSec 4 -ErrorAction Stop -Headers @{ 'User-Agent' = $ua }
        } @("https://api.github.com/repos/$Repo/releases/latest", "LLMCleaner/$Version")
        $newVersion = [version]($r.tag_name.TrimStart('v'))
        if ($newVersion -le [version]$Version) { return }
        $setup = $r.assets | Where-Object { $_.name -like 'LLMCleaner-Setup-*.exe' } | Select-Object -First 1
        $script:AppUpdate = @{ Version = "$newVersion"; Page = $r.html_url; Installer = $setup.browser_download_url; Name = $setup.name }
        Write-Log "Dostepna aktualizacja: $newVersion"
    }
    catch { Write-Log "Sprawdzanie aktualizacji: $($_.Exception.Message)" }
}

# Pobiera instalator i uruchamia go jako zwykly uzytkownik (przez Eksplorator), zeby
# aktualizacja trafila w ten sam tryb instalacji co poprzednio. Zwraca $true, gdy wystartowal.
function Install-AppUpdate {
    $a = $script:AppUpdate
    $isInstalled = Test-Path -LiteralPath (Join-Path $AppDir 'unins000.exe')
    if (-not $isInstalled -or -not $a.Installer) {
        Write-Line ((L '   Wersja portable - pobierz nową wersję ze strony: {0}' '   Portable version - download the new version from: {0}') -f $a.Page) 'Yellow'
        return $false
    }
    $file = Join-Path $env:TEMP $a.Name
    Write-Line ((L '   Pobieram {0}...' '   Downloading {0}...') -f $a.Name) 'Gray'
    try {
        Invoke-Background {
            param($url, $file)
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest $url -OutFile $file -UseBasicParsing -ErrorAction Stop
        } @($a.Installer, $file) | Out-Null
    }
    catch { Write-Line ((L '   Nie udało się pobrać: {0}' '   Download failed: {0}') -f $_.Exception.Message) 'Yellow'; return $false }
    Write-Log "Aktualizacja: uruchamiam $file"
    Start-Process explorer.exe -ArgumentList "`"$file`""
    $true
}
