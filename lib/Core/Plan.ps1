<#
    LLMCleaner - cleanup plan (rules, no model), report and summary
#>

# Categories: selected when they contain anything. Recycle Bin (irreversible), DNS and "manual only"
# categories are always unselected. Leftovers: selected at high and medium confidence.
function Build-Plan {
    foreach ($k in $script:Categories) {
        $k.Selected = -not $k.OptIn -and -not $k.Blocker -and $k.Type -in 'folder', 'thumbnails' -and $k.Bytes -gt 0
    }
    # Large files and folders (own tab on the plan page) are more often something the user still wants
    # than a leftover - never selected in advance
    foreach ($p in $script:Leftovers) { $p.Selected = $p.Confidence -in 'high', 'medium' -and -not (Test-LargeItem $p) }
}

# Large item: a big file found in the profile or Downloads, or a leftover folder of 1 GB or more
$LargeItemSize = 1GB
function Test-LargeItem($p) { [bool]$p.LargeFile -or ($p.Type -in 'folder', 'file' -and [double]$p.Bytes -ge $LargeItemSize) }

function Get-LockedTotal { [double](@($script:Categories | Where-Object { $_.Selected } | ForEach-Object { [double]$_.Locked }) | Measure-Object -Sum).Sum }

function Get-SelectedTotal { [double](@($script:Categories) + @($script:Leftovers) | Where-Object { $_.Selected } | ForEach-Object { [double]$_.Bytes } | Measure-Object -Sum).Sum }

function Get-ReportJson {
    # Ready list sorted largest first - a small model compares sizes written as text in different sections badly
    $largestFirst = @(@($script:Categories) + @($script:Leftovers) | Where-Object { $_.Bytes -gt 0 } |
            Sort-Object { [double]$_.Bytes } -Descending | Select-Object -First 15 | ForEach-Object {
                @{ item = $(if ($_.Path -and -not $_.Description) { $_.Path } else { $_.Name }); size = (Format-Size $_.Bytes); selected = [bool]$_.Selected } })
    $report = @{
        plan_largest_first      = $largestFirst
        selected_total          = (Format-Size (Get-SelectedTotal))
        drives                  = $script:ProfileScan.Drives
        categories              = @($script:Categories | ForEach-Object {
                @{ id = $_.Id; name = $_.Name; description = $_.Description; selected = [bool]$_.Selected
                    size = (Format-CategorySize $_); opt_in = [bool]$_.OptIn; blocker = $_.Blocker
                } })
        leftovers               = @($script:Leftovers | ForEach-Object {
                @{ id = $_.Id; type = $_.Type; path = $_.Path; selected = [bool]$_.Selected
                    size = $(if (Test-GoesToRecycleBin $_) { Format-Size $_.Bytes } else { '-' })
                    last_modified = $(if ($_.LastWrite) { $_.LastWrite.ToString('yyyy-MM-dd') }); confidence = $_.Confidence
                    reason = $_.Reason; what_it_is = $_.Ai
                } })
        largest_profile_folders = $script:ProfileScan.Profile
        large_appdata_folders   = $script:ProfileScan.AppData
        largest_programs        = $script:ProfileScan.Programs
        system                  = $script:ProfileScan.System
        disk_analysis           = @($script:Analyses.Values | ForEach-Object {
                @{ drive = "$($_.Letter):"; items = @(@($_.Folders) + @($_.Files) | ForEach-Object {
                            @{ path = $_.Path; size = (Format-Size $_.Bytes); hint = $_.Hint; what_it_is = $_.Ai } })
                } })
        startup                 = @($script:Startup | Where-Object { $_ } | ForEach-Object {
                @{ name = $_.Name; enabled = [bool]$_.IsEnabled; publisher = $_.Publisher; source = $_.Source; command = $_.Command
                    protected = $_.Protected; what_it_is = $_.Ai
                } })
    }
    ConvertTo-Json -InputObject $report -Depth 10 -Compress
}

# Report for the chat: same as Get-ReportJson, but trimmed to a size a small model can read in full.
# The full report after a big scan (hundreds of items) overflowed the model's context window - Ollama then cut
# the start of the conversation including the instructions, and the model did not answer or took minutes.
# The largest items stay, the rest is counted in the summary. Limit in characters (about 2.5 chars per token).
$ChatReportLimit = 14000
function Get-Shortened([string]$t, [int]$n) { if (-not $t -or $t.Length -le $n) { return $t }; $t.Substring(0, $n - 1) + '…' }
function Get-ChatReport([int]$limit = $ChatReportLimit) {
    $leftoverList = @($script:Leftovers | Where-Object { $_ } | Sort-Object { [double]$_.Bytes } -Descending)
    $ticked = @($leftoverList | Where-Object { $_.Selected })
    foreach ($n in 60, 40, 25, 15, 8, 4) {
        $shownItems = @($leftoverList | Select-Object -First $n)
        $rest = @($leftoverList | Select-Object -Skip $n)
        $report = [ordered]@{
            summary          = [ordered]@{
                selected_total     = (Format-Size (Get-SelectedTotal))
                leftovers_total    = $leftoverList.Count
                leftovers_selected = $ticked.Count
                leftovers_hidden   = $rest.Count
                hidden_total       = (Format-Size ([double](@($rest | ForEach-Object { [double]$_.Bytes }) | Measure-Object -Sum).Sum))
            }
            drives           = $script:ProfileScan.Drives
            system           = $script:ProfileScan.System
            categories       = @($script:Categories | Where-Object { $_ } | ForEach-Object {
                    $k = [ordered]@{ name = $_.Name; size = (Format-CategorySize $_); selected = [bool]$_.Selected }
                    if ($_.OptIn) { $k.opt_in = $true }
                    if ($_.Blocker) { $k.blocker = Get-Shortened "$($_.Blocker)" 80 }
                    $k })
            leftovers        = @($shownItems | ForEach-Object {
                    $x = [ordered]@{ id = $_.Id; type = $_.Type; path = (Get-Shortened (Format-Leftover $_) 110); size = (Format-LeftoverSize $_)
                        selected = [bool]$_.Selected; confidence = $_.Confidence; reason = (Get-Shortened $_.Reason 90)
                    }
                    if ($_.LastWrite) { $x.last_modified = $_.LastWrite.ToString('yyyy-MM-dd') }
                    if ($_.Ai) { $x.what_it_is = Get-Shortened $_.Ai 80 }
                    $x })
            largest_programs = @($script:ProfileScan.Programs | Select-Object -First ([Math]::Min($n, 12)))
            largest_folders  = @(@($script:ProfileScan.Profile) + @($script:ProfileScan.AppData) | Select-Object -First ([Math]::Min($n, 12)))
            disk_analysis    = @($script:Analyses.Values | ForEach-Object {
                    @{ drive = "$($_.Letter):"; items = @(@($_.Folders) + @($_.Files) | Sort-Object { [double]$_.Bytes } -Descending |
                                Select-Object -First ([Math]::Min($n, 15)) | ForEach-Object {
                                    $a = [ordered]@{ path = (Get-Shortened $_.Path 110); size = (Format-Size $_.Bytes) }
                                    if ($_.Hint) { $a.hint = Get-Shortened $_.Hint 80 }
                                    if ($_.Ai) { $a.what_it_is = Get-Shortened $_.Ai 80 }
                                    $a })
                        } })
                startup      = @($script:Startup | Where-Object { $_ } | Select-Object -First ([Math]::Min($n, 30)) | ForEach-Object {
                        $a = [ordered]@{ name = $_.Name; enabled = [bool]$_.IsEnabled }
                        if ($_.Publisher) { $a.publisher = Get-Shortened $_.Publisher 40 }
                        if ($_.Ai) { $a.what_it_is = Get-Shortened $_.Ai 60 }
                        $a })
            }
            $json = ConvertTo-Json -InputObject $report -Depth 8 -Compress
            if ($json.Length -le $limit) { return $json }
        }
        $json
    }

    # Summary before cleanup: list of lines @{ T = text; K = color } or $null when nothing is selected
    function Get-Summary {
        $selected = @($script:Categories | Where-Object { $_.Selected })
        $selectedLeftovers = @($script:Leftovers | Where-Object { $_.Selected })
        if (-not $selected.Count -and -not $selectedLeftovers.Count) { return $null }
        $lines = [System.Collections.Generic.List[object]]::new()
        function Add-Entry($t, $k = 'Gray') { $lines.Add(@{ T = $t; K = $k }) }
        if ($selected.Count) {
            Add-Entry (L 'Zostanie wyczyszczone:' 'To be cleaned:') 'White'
            foreach ($k in $selected) {
                $sizeText = if (Test-MeasurableCategory $k) { Format-Size $k.Bytes } elseif ($k.Type -eq 'dns') { '-' } else { L 'nieznane' 'unknown' }
                Add-Entry ("  - {0,-52} {1,10}" -f $k.Name, $sizeText)
            }
            $total = ($selected | ForEach-Object { [double]$_.Bytes } | Measure-Object -Sum).Sum
            Add-Entry ''
            Add-Entry ((L 'Zwolnione miejsce   : ok. {0}' 'Space freed         : about {0}') -f (Format-Size $total)) 'Green'
            Add-Entry ((L 'Wolne na {1} teraz  : {0}' 'Free on {1} now     : {0}') -f (Format-Size $script:FreeBefore), $Sys)
            Add-Entry ((L 'Wolne na {1} po     : ok. {0}' 'Free on {1} after   : about {0}') -f (Format-Size ($script:FreeBefore + $total)), $Sys)
            $lockedBytes = Get-LockedTotal
            if ($lockedBytes) { Add-Entry ((L 'Zablokowane         : {0} (pliki w użyciu - nie zostaną usunięte, nie są wliczone)' 'Locked              : {0} (files in use - not deleted, not included)') -f (Format-Size $lockedBytes)) 'Yellow' }
            Add-Entry (L '(część plików może być w użyciu - wtedy zostaną pominięte i zysk będzie mniejszy)' '(some files may be in use - they are skipped and the gain will be smaller)') 'DarkGray'
        }
        $toBin = @($selectedLeftovers | Where-Object { Test-GoesToRecycleBin $_ })
        $regItems = @($selectedLeftovers | Where-Object { $_.Type -in 'registry', 'regvalue' })
        $taskItems = @($selectedLeftovers | Where-Object { $_.Type -eq 'task' })
        if ($selectedLeftovers.Count) {
            Add-Entry ''
            Add-Entry (L 'Pozostałości po odinstalowanych programach i grach:' 'Leftovers of uninstalled programs and games:') 'White'
            foreach ($p in $selectedLeftovers) {
                Add-Entry ("  - {0,-52} {1,10}" -f (Format-Leftover $p), (Format-LeftoverSize $p))
            }
            if ($toBin.Count) {
                $binBytes = ($toBin | ForEach-Object { [double]$_.Bytes } | Measure-Object -Sum).Sum
                Add-Entry ((L 'Do Kosza            : {0} ({1}) - miejsce zwolni się po opróżnieniu Kosza' 'To the Recycle Bin  : {0} ({1}) - the space is freed when you empty the Recycle Bin') -f $toBin.Count, (Format-Size $binBytes))
            }
            if ($regItems.Count) {
                Add-Entry ((L 'Klucze rejestru     : {0} - kopia .reg w logs\kopie_rejestru + punkt przywracania systemu' 'Registry keys       : {0} - .reg backup in logs\kopie_rejestru + System Restore point') -f $regItems.Count)
            }
            if ($taskItems.Count) {
                Add-Entry ((L 'Zadania Harmonogramu: {0} - kopia .xml w logs\kopie_rejestru' 'Scheduled tasks     : {0} - .xml backup in logs\kopie_rejestru') -f $taskItems.Count)
            }
        }
        $notes = @()
        if ($selected | Where-Object { $_.Id -eq 'recyclebin' }) { $notes += L 'Kosz zostanie opróżniony NIEODWRACALNIE (przed przeniesieniem pozostałości).' 'The Recycle Bin is emptied PERMANENTLY (before leftovers are moved to it).' }
        if ($selected | Where-Object { $_.Type -eq 'thumbnails' }) { $notes += L 'Eksplorator zostanie zrestartowany - pasek zadań zniknie na kilka sekund.' 'File Explorer restarts - the taskbar disappears for a few seconds.' }
        if ($selected | Where-Object { $_.Type -eq 'dism' }) { $notes += L 'DISM potrwa kilka minut; potem nie odinstalujesz starszych aktualizacji.' 'DISM takes a few minutes; older updates can no longer be uninstalled afterwards.' }
        if ($selected | Where-Object { $_.Type -eq 'driverstore' }) { $notes += L 'Usunięte starsze wersje sterowników nie wrócą - przed usunięciem powstanie punkt przywracania.' 'Removed older driver versions cannot be brought back - a System Restore point is created first.' }
        if ($selected | Where-Object { $_.Type -eq 'winold' }) { $notes += L 'Po usunięciu Windows.old nie da się wrócić do poprzedniej wersji Windows.' 'After removing Windows.old you cannot go back to the previous Windows version.' }
        if ($selected | Where-Object { $_.Processes }) { $notes += L 'Nie otwieraj przeglądarki w trakcie czyszczenia.' 'Do not open a browser while cleaning.' }
        if ($selectedLeftovers | Where-Object { $_.Confidence -eq 'low' }) { $notes += L 'Zaznaczono pozycje o niskiej pewności (zapisy gier / duże pliki) - upewnij się, że ich nie potrzebujesz.' 'Low-confidence items are selected (game saves / large files) - make sure you do not need them.' }
        if ($notes.Count) { Add-Entry ''; foreach ($u in $notes) { Add-Entry "! $u" 'Yellow' } }
        , $lines
    }
