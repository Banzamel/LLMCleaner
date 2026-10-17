<#
    LLMCleaner - disk analysis: what takes up space, fixed and AI advice
#>

# View only - nothing here goes into the plan. The scanner is in C#, because a PowerShell loop
# takes minutes over a million files. It does not follow junctions/symlinks and skips cloud-only
# files (OneDrive). Hard links (WinSxS) are counted multiple times, like in Explorer.
function Initialize-ScannerType {
    if ('LlmScanner' -as [type]) { return }
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $AppDir 'lib\Core\cs\LlmScanner.cs')))
}

# Known locations - hint without the model
$KnownPlaces = @(
    @{ W = '\\Windows\\WinSxS$'; P = (L 'Magazyn komponentów Windows. Zmniejsza go tylko DISM (kategoria w planie); rozmiar zawyżony przez twarde linki.' 'Windows component store. Only DISM shrinks it (a plan category); the size is inflated by hard links.') }
    @{ W = '\\Windows\\Installer$'; P = (L 'Pamięć instalatorów MSI - nie usuwaj ręcznie, psuje odinstalowywanie programów.' 'MSI installer cache - do not delete by hand, it breaks uninstalling programs.') }
    @{ W = '\\Windows\\SoftwareDistribution$'; P = (L 'Aktualizacje Windows - kategoria „Cache Windows Update” w planie.' 'Windows updates - the "Windows Update cache" plan category.') }
    @{ W = '\\Windows\\System32\\DriverStore'; P = (L 'Magazyn sterowników (np. sterownik karty graficznej). Nie usuwaj ręcznie - stare wersje usuwa kategoria „Starsze wersje sterowników” w planie.' 'Driver store (e.g. the graphics driver). Do not delete by hand - the "Older driver versions" plan category removes old versions.') }
    @{ W = '\\Windows\\servicing'; P = (L 'Pliki obsługi aktualizacji Windows - zarządza nimi system.' 'Windows update servicing files - managed by the system.') }
    @{ W = '\\Windows\.old$'; P = (L 'Poprzednia wersja Windows - kategoria w planie.' 'Previous Windows version - a plan category.') }
    @{ W = '^[A-Z]:\\pagefile\.sys$'; P = (L 'Plik stronicowania (pamięć wirtualna). Rozmiar ustawia się w Ustawieniach systemu.' 'Page file (virtual memory). Its size is set in the system settings.') }
    @{ W = '^[A-Z]:\\hiberfil\.sys$'; P = (L 'Hibernacja i szybkie uruchamianie. „powercfg /h off” usuwa go, ale wyłącza hibernację.' 'Hibernation and fast startup. "powercfg /h off" removes it but turns hibernation off.') }
    @{ W = '^[A-Z]:\\swapfile\.sys$'; P = (L 'Plik wymiany aplikacji ze Sklepu - zarządza nim Windows.' 'Swap file for Store apps - managed by Windows.') }
    @{ W = '\\steamapps\\common\\[^\\]+$'; P = (L 'Gra ze Steama - odinstaluj ją w Steamie.' 'Steam game - uninstall it in Steam.') }
    @{ W = '\\steamapps\\(workshop|shadercache|downloading)'; P = (L 'Dane Steama (Workshop, shadery, pobieranie).' 'Steam data (Workshop, shaders, downloads).') }
    @{ W = '\\Epic Games\\[^\\]+$'; P = (L 'Gra z Epic Games - odinstaluj ją w launcherze Epic.' 'Epic Games game - uninstall it in the Epic launcher.') }
    @{ W = '\\swap\.vhdx$'; P = (L 'Plik wymiany WSL - znika po „wsl --shutdown”.' 'WSL swap file - removed by "wsl --shutdown".') }
    @{ W = '\\AppData\\Local\\Temp(\\[^\\]+)?$'; P = (L 'Pliki tymczasowe - kategoria TEMP w planie (pliki w użyciu są pomijane).' 'Temporary files - the TEMP plan category (files in use are skipped).') }
    @{ W = '(ext4|docker_data)\.vhdx$|DockerDesktopWSL|\\Docker\\wsl'; P = (L 'Dysk WSL/Docker. Miejsce zwalnia „docker system prune”, a potem kompaktowanie dysku VHDX.' 'WSL/Docker disk. "docker system prune" and then compacting the VHDX frees space.') }
    @{ W = '\\AppData\\Local\\Packages\\[^\\]+$'; P = (L 'Dane aplikacji ze Sklepu Microsoft - wyczyść lub odinstaluj w Ustawieniach > Aplikacje.' 'Microsoft Store app data - reset or uninstall it in Settings > Apps.') }
    @{ W = '\\node_modules$'; P = (L 'Zależności projektu Node.js - „npm install” odtworzy je w razie potrzeby.' 'Node.js project dependencies - "npm install" restores them when needed.') }
    @{ W = '\\\.(gradle|m2|nuget|cargo|rustup)$'; P = (L 'Cache narzędzi programistycznych.' 'Developer tool cache.') }
    @{ W = '\\(Downloads|Pobrane)$'; P = (L 'Pobrane pliki - często stare instalatory i archiwa.' 'Downloaded files - often old installers and archives.') }
    @{ W = '\\LLMCleaner\\ai$'; P = (L 'Silnik AI i modele LLMCleanera.' 'The LLMCleaner AI engine and models.') }
    @{ W = '\.(iso|vhdx?|vmdk|qcow2)$'; P = (L 'Obraz dysku lub maszyny wirtualnej.' 'Disk or virtual machine image.') }
)
function Get-PlaceHint([string]$s) { foreach ($z in $KnownPlaces) { if ($s -match $z.W) { return $z.P } }; $null }

function Invoke-DriveScan([string]$letter) {
    Initialize-ScannerType
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$letter`:'"
    $usedBytes = [double]$d.Size - [double]$d.FreeSpace
    $threshold = if ($usedBytes -gt 1TB) { 2GB } else { 1GB }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $task = [LlmScanner]::Start("$letter`:\", 6, $threshold, 1GB)
    while (-not $task.Wait(200)) {
        Write-Status ((L '   przejrzano {0:N0} plików ({1:N0} s)...' '   scanned {0:N0} files ({1:N0} s)...') -f [LlmScanner]::Counter, $timer.Elapsed.TotalSeconds)
        if ($script:Mode -eq 'window') { [Windows.Forms.Application]::DoEvents() }
    }
    $w = $task.Result
    Complete-Status ((L '   przejrzano {0:N0} plików w {1:N0} s.                 ' '   scanned {0:N0} files in {1:N0} s.                 ') -f $w.FileCount, $timer.Elapsed.TotalSeconds)

    # Most specific large folders: no large subfolder, or a large "rest" outside them
    $byPath = @{}; foreach ($f in $w.Folders) { $byPath[$f.Path] = $f }
    $largeChildren = @{}
    foreach ($f in $w.Folders) {
        $parentDir = [IO.Path]::GetDirectoryName($f.Path)
        if ($parentDir -and $byPath.ContainsKey($parentDir)) { $largeChildren[$parentDir] += [double]$f.Bytes }
    }
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $w.Folders) {
        $children = [double]$largeChildren[$f.Path]
        if ($children -eq 0) { $b = [double]$f.Bytes; $rest = $false }
        elseif ($f.Bytes - $children -ge $threshold) { $b = $f.Bytes - $children; $rest = $true }
        else { continue }
        $items.Add(@{ Type = 'folder'; Path = $f.Path; Bytes = $b; Remainder = $rest; Files = $f.Files
                LastWrite = $f.LastWrite; Hint = (Get-PlaceHint $f.Path)
            })
    }
    $folders = @($items | Sort-Object { $_.Bytes } -Descending | Select-Object -First 20)
    $files = @($w.Files | Sort-Object Bytes -Descending | Select-Object -First 10 | ForEach-Object {
            @{ Type = 'file'; Path = $_.Path; Bytes = [double]$_.Bytes; LastWrite = $_.LastWrite; Hint = (Get-PlaceHint $_.Path) } })

    # Restore points and shadow copies - invisible to the scanner (System Volume Information)
    $shadowBytes = 0.0
    $volume = Get-CimInstance Win32_Volume | Where-Object { $_.DriveLetter -eq "$letter`:" } | Select-Object -First 1
    foreach ($s in Get-CimInstance Win32_ShadowStorage) { if ($volume -and $s.Volume.DeviceID -eq $volume.DeviceID) { $shadowBytes += [double]$s.UsedSpace } }

    $i = 0
    foreach ($p in @($folders) + @($files)) { $i++; $p.Id = "A$i" }
    Write-Log ("Analysis {0}: {1:N0} files, {2} folders, {3} files >1GB, access denied: {4}" -f $letter, $w.FileCount, $folders.Count, $files.Count, $w.Denied)
    @{ Letter = $letter; Size = [double]$d.Size; Free = [double]$d.FreeSpace; ScannedBytes = [double]$w.Bytes
        Folders = $folders; Files = $files; ShadowCopies = $shadowBytes; Threshold = $threshold
    }
}

function Get-DriveAnalysis([string]$letter) {
    if (-not $script:Analyses.ContainsKey($letter)) {
        Write-Line ((L '   Skanuję dysk {0}: (zwykle 30 s - 3 min)...' '   Scanning drive {0}: (usually 30 s - 3 min)...') -f $letter) 'DarkGray'
        $script:Analyses[$letter] = Invoke-DriveScan $letter
        $script:Conversation = $null   # new data for the chat
    }
    $script:Analyses[$letter]
}

# The model picks advice only from this list (enum in the schema) - it cannot advise manual deletion
$AnalysisAdvice = if ($Language -ne 'pl') {
    @('leave it - part of Windows', 'uninstall in Settings > Apps', 'uninstall the game in its launcher',
        'clean it in the program settings', 'review and move to another drive', 'review the contents manually',
        'the TEMP plan category cleans it')
}
else {
    @('zostaw - część systemu', 'odinstaluj w Ustawieniach > Aplikacje', 'odinstaluj grę w jej launcherze',
        'wyczyść w ustawieniach programu', 'przejrzyj i przenieś na inny dysk', 'przejrzyj zawartość ręcznie',
        'oczyści to kategoria TEMP w planie')
}
$AnalysisAdviceEn = $AnalysisAdvice
$AnalysisAdvice = @($AnalysisAdvice | ForEach-Object { if ($Language -eq 'pl') { $_ } else { Get-Translation $_ } })

# System, program and TEMP folders: the program sets the advice, not the model
function Get-FixedAdvice([string]$s) {
    if ($s -match '\\AppData\\Local\\Temp(\\|$)') { return $AnalysisAdvice[6] }
    if ($s -match '^[A-Z]:\\(Windows|ProgramData)(\\|$)' -or $s -match '^[A-Z]:\\[^\\]+\.sys$') { return $AnalysisAdvice[0] }
    if ($s -match '^[A-Z]:\\Program Files( \(x86\))?(\\(Microsoft[^\\]*|Windows[^\\]*|Common Files))?$') { return $AnalysisAdvice[0] }
    if ($s -match '^[A-Z]:\\Program Files( \(x86\))?\\') { return $AnalysisAdvice[1] }
    $null
}

$AnalysisSchema = @{
    type       = 'object'
    properties = @{
        items = @{ type = 'array'; items = @{ type = 'object'
                properties                         = @{ id = @{ type = 'string' }; description = @{ type = 'string' }; advice = @{ type = 'string'; enum = $AnalysisAdvice } }
                required                           = @('id', 'description', 'advice')
            }
        }
    }
    required   = @('items')
}

$PromptAnalysis = if ($Language -ne 'pl') {
    @'
You are LLMCleaner, a Windows cleanup assistant. You get a list of the largest folders and files on a drive
(path, size, last change date, sometimes a hint from the program). For EACH item give:
- "description": what it is (program, game, user data, cache, part of Windows) - based on the path and the hint,
- "advice": one of the allowed values - what the user can safely do.
Rules:
- Everything in C:\Windows, C:\ProgramData and .sys files is part of Windows: "leave it - part of Windows".
- Games (steamapps, Epic Games) -> "uninstall the game in its launcher"; programs -> "uninstall in Settings > Apps".
- User data (documents, projects, downloads, unknown profile folders) -> "review the contents manually"
  or "review and move to another drive".
- If there is a hint from the program, the description must agree with it.
- An old last change date may mean an unused program or game - you may mention it in the description.
- Do not invent program names that are not in the path. If you do not know, write "unknown data".
- Description max. 12 words, in English.
'@
}
else {
    @'
Jesteś LLMCleaner - asystentem sprzątania Windows. Dostajesz listę największych folderów i plików na dysku
(ścieżka, rozmiar, data ostatniej zmiany, czasem podpowiedź programu). Dla KAŻDEJ pozycji podaj:
- "description": czym to jest (program, gra, dane użytkownika, cache, część systemu) - na podstawie ścieżki i podpowiedzi,
- "advice": jedna z dozwolonych wartości - co użytkownik może bezpiecznie zrobić.
Zasady:
- Wszystko w C:\Windows, C:\ProgramData i plikach .sys to część systemu: rada "zostaw - część systemu".
- Gry (steamapps, Epic Games) -> "odinstaluj grę w jej launcherze"; programy -> "odinstaluj w Ustawieniach > Aplikacje".
- Dane użytkownika (dokumenty, projekty, pobrane, nieznane foldery w profilu) -> "przejrzyj zawartość ręcznie"
  albo "przejrzyj i przenieś na inny dysk".
- Jeśli jest podpowiedź programu, opis musi być z nią zgodny.
- Stara data ostatniej zmiany może oznaczać nieużywany program lub grę - możesz o tym wspomnieć w opisie.
- Nie zmyślaj nazw programów, których nie ma w ścieżce. Jeśli nie wiesz, napisz "nieznane dane".
- Opis maks. 12 słów, po polsku.
'@
}
$PromptAnalysis = Convert-Prompt $PromptAnalysis ($AnalysisAdviceEn + 'unknown data')

# Model descriptions and advice for disk analysis. Returns the number of described items (or -1 on error).
function Invoke-AnalysisAi($a) {
    if (-not (Initialize-Model)) { return -1 }
    $list = @(@($a.Folders) + @($a.Files) | ForEach-Object {
            @{ id = $_.Id; type = $_.Type; path = $_.Path; size = (Format-Size $_.Bytes); hint = $_.Hint
                last_modified = $(if ($_.LastWrite -gt [datetime]'1980-01-01') { $_.LastWrite.ToString('yyyy-MM-dd') })
            } })
    Write-Line ((L '   Model opisuje {0} pozycji (ok. 20-40 s)...' '   The model is describing {0} items (about 20-40 s)...') -f $list.Count) 'DarkGray'
    try {
        $answer = Invoke-Ollama @(@{ role = 'system'; content = $PromptAnalysis },
            @{ role = 'user'; content = (ConvertTo-Json -InputObject $list -Depth 5 -Compress) }) $AnalysisSchema
        $n = 0
        foreach ($w in @(($answer | ConvertFrom-Json -ErrorAction Stop).items)) {
            $p = @(@($a.Folders) + @($a.Files)) | Where-Object { $_.Id -eq $w.id } | Select-Object -First 1
            if ($p -and $w.description) {
                $advice = Get-FixedAdvice $p.Path
                if (-not $advice) { $advice = if ($w.advice -in $AnalysisAdvice) { $w.advice } else { $AnalysisAdvice[5] } }
                $p.Ai = "$($w.description.Trim().TrimEnd('.;')). $(L 'Rada' 'Advice'): $advice."; $n++
            }
        }
        Write-Line ((L '   Gotowe - opisano {0} pozycji.' '   Done - {0} items described.') -f $n) 'Green'
        Write-Log "Analysis - model descriptions: $answer"
        $script:Conversation = $null
        $n
    }
    catch { Write-Log "Model error: $($_.Exception.Message)"; Write-Line ((L '   Błąd modelu: {0}' '   Model error: {0}') -f $_.Exception.Message) 'Yellow'; -1 }
}
