<#
    LLMCleaner - program updates from GitHub
#>

# One request to GitHub at startup (no data about the computer); -NoUpdateCheck turns it off.
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
        Write-Log "Update available: $newVersion"
    }
    catch { Write-Log "Update check: $($_.Exception.Message)" }
}

# Downloads the installer and runs it as a normal user (via Explorer) so the update
# lands in the same install mode as before. Returns $true when it started.
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
    Write-Log "Update: starting $file"
    Start-Process explorer.exe -ArgumentList "`"$file`""
    $true
}
