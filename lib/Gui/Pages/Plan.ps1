<#
    LLMCleaner - plan page (cleanup plan): two tabs (plan, large files and folders), filter, search, sorting.
    Rows and columns are in PlanRows.ps1.
#>

$script:PlanTab = 'plan'
$script:PlanSort = @{ Key = 'size'; Desc = $true }
# Groups start collapsed (header and total only); a click on the header expands it. Search shows everything.
$script:PlanExpanded = @{}

function Test-PlanFilter($o, [bool]$cat) {
    switch ($script:PlanFilter) {
        'selected' { if (-not $o.Selected) { return $false } }
        'optin' { if (-not ($o.OptIn -or $o.Confidence -eq 'low')) { return $false } }
    }
    $q = $script:UI.Search.Text.Trim()
    if (-not $q) { return $true }
    $t = if ($cat) { "$($o.Name) $($o.Description) $($o.Note)" } else { "$(Format-Leftover $o) $($o.Path) $($o.Reason) $($o.Ai)" }
    $t.IndexOf($q, [StringComparison]::CurrentCultureIgnoreCase) -ge 0
}

function Get-GroupTotal($list) {
    $z = @($list | Where-Object { $_.Selected })
    $b = [double]($z | ForEach-Object { [double]$_.Bytes } | Measure-Object -Sum).Sum
    if (-not $z.Count) { return L 'nic nie zaznaczono' 'nothing selected' }
    if ($b -gt 0) { (L 'zaznaczone {0}' '{0} selected') -f (Format-Size $b) } else { (L 'zaznaczone: {0}' 'selected: {0}') -f $z.Count }
}

function Get-LargeItems { @($script:Leftovers | Where-Object { $_ -and (Test-LargeItem $_) }) }

# Adds a group header and its rows (filtered and sorted) to the list
function Add-PlanGroup($rows, [string]$key, [string]$title, $all, [bool]$cat, [double]$max) {
    $shown = @(Sort-PlanItems @($all | Where-Object { Test-PlanFilter $_ $cat }) $cat)
    if (-not $shown.Count) { return }
    $everything = $all
    $collapsed = -not $script:PlanExpanded[$key] -and -not $script:UI.Search.Text.Trim()
    $rows.Add(@{ Section = $true; H = (Px 42); Text = $title; Key = $key; Collapsible = $true; Collapsed = $collapsed; Count = $shown.Count
            RightText = { Get-GroupTotal $everything }.GetNewClosure()
        })
    if ($collapsed) { return }
    foreach ($o in $shown) { $rows.Add(@{ H = (Px 60); Obj = $o; IsCategory = $cat; Max = $max }) }
}

function Update-PlanPage {
    $lv = $script:UI.LvPlan
    $rows = [System.Collections.Generic.List[object]]::new()
    $large = Get-LargeItems
    if ($script:PlanTab -eq 'large') {
        $max = [double](@($large) | ForEach-Object { [double]$_.Bytes } | Measure-Object -Maximum).Maximum
        Add-PlanGroup $rows 'largefolders' (L 'Duże foldery (ponad 1 GB) - zwykle żywe gry i programy, sprawdź każdy' 'Large folders (over 1 GB) - often live games and programs, check each one') @($large | Where-Object { $_.Type -eq 'folder' }) $false $max
        Add-PlanGroup $rows 'largefiles' (L 'Duże pliki w profilu i w Pobranych' 'Large files in the profile and in Downloads') @($large | Where-Object { $_.Type -eq 'file' }) $false $max
    }
    else {
        $cat = @($script:Categories | Where-Object { $_.Bytes -gt 0 -or $_.Selected -or ($_.Type -in 'dns', 'dism', 'docker', 'dockerall') })
        $left = @($script:Leftovers | Where-Object { $_ -and -not (Test-LargeItem $_) })
        $max = [double](@($cat) + @($left) | ForEach-Object { [double]$_.Bytes } | Measure-Object -Maximum).Maximum
        Add-PlanGroup $rows 'categories' (L 'Kategorie czyszczenia - odtwarzają się same' 'Cleanup categories - they rebuild themselves') $cat $true $max
        Add-PlanGroup $rows 'leftovers' (L 'Pozostałości po odinstalowanych programach i grach' 'Leftovers of uninstalled programs and games') @($left | Where-Object { Test-GoesToRecycleBin $_ }) $false $max
        Add-PlanGroup $rows 'registry' (L 'Rejestr i zadania' 'Registry and tasks') @($left | Where-Object { -not (Test-GoesToRecycleBin $_) }) $false $max
    }
    $lv.Tag.EmptyText = if (-not $script:Scanned) { L 'Plan pojawi się po skanie. Wróć do Przeglądu i kliknij „Skanuj”.' 'The plan appears after a scan. Go back to Overview and click "Scan".' }
    elseif ($script:PlanTab -eq 'large' -and -not $large.Count) { L 'Skan nie znalazł dużych plików ani folderów.' 'The scan found no large files or folders.' }
    else { L 'Nic nie pasuje do wyszukiwania albo filtra.' 'Nothing matches the search or filter.' }
    Set-Rows $lv $rows
    if ($script:UI.PlanTabs) { $script:UI.PlanTabs.Invalidate() }
    Update-PlanTotal
}

function Update-PlanTotal {
    $u = $script:UI
    $selected = @(@($script:Categories) + @($script:Leftovers) | Where-Object { $_ -and $_.Selected })
    $u.Total.Text = (L 'Zaznaczone: {0}' 'Selected: {0}') -f (Format-Size (Get-SelectedTotal))
    $t = (L 'Pozycji: {0}' 'Items: {0}') -f $selected.Count
    $bigSel = @(Get-LargeItems | Where-Object { $_.Selected }).Count
    if ($bigSel) { $t += ' · ' + ((L 'w tym duże: {0}' 'of which large: {0}') -f $bigSel) }
    $lockedSum = Get-LockedTotal
    if ($lockedSum) { $t += ' · ' + ((L '{0} zablokowane przez działające programy' '{0} locked by running programs') -f (Format-Size $lockedSum)) }
    $u.TotalNote.Text = $t
    $u.LvPlan.Invalidate()
    Update-Overview
}

function New-PlanPage {
    $s = $script:Style
    $page = New-Page
    $n = New-PageHeader (L 'Plan czyszczenia' 'Cleanup plan') (L 'Kliknij nagłówek grupy, żeby ją rozwinąć. Pole po lewej zaznacza pozycję, kliknięcie nazwy pokazuje pełny opis, a nagłówek kolumny sortuje listę. Pliki i foldery trafiają do Kosza, rejestr i zadania mają kopię i punkt przywracania.' 'Click a group header to expand it. The box on the left ticks an item, clicking its name shows the full description and a column header sorts the list. Files and folders go to the Recycle Bin; registry entries and tasks get a backup and a restore point.')

    # Tabs: the plan and large files/folders (never ticked in advance)
    $tabBar = New-Control Panel @{ Dock = 'Top'; Height = (Px 40) }
    $tabs = New-Segment @(
        @{ Id = 'plan'; T = { (L 'Plan ({0})' 'Plan ({0})') -f (@($script:Categories | Where-Object { $_.Bytes -gt 0 }).Count + @($script:Leftovers | Where-Object { $_ -and -not (Test-LargeItem $_) }).Count) } }
        @{ Id = 'large'; T = { (L 'Duże pliki i foldery ({0})' 'Large files and folders ({0})') -f @(Get-LargeItems).Count } }
    ) { $script:PlanTab } { param($id) $script:PlanTab = $id; if ($script:Scanned) { Update-PlanPage } } 420
    $tabNote = New-Label (L 'Duże pozycje nigdy nie są zaznaczane z góry.' 'Large items are never ticked in advance.') @{ Dock = 'Fill'; ForeColor = $s.TextDim; Font = $s.Small; TextAlign = 'MiddleLeft'; Padding = (New-Padding 14 0 0 0); AutoEllipsis = $true }
    Add-Docked $tabBar @($tabs, $tabNote)
    $script:UI.PlanTabs = $tabs

    # Toolbar: search, filter, selection buttons
    $bar = New-Control Panel @{ Dock = 'Top'; Height = (Px 40) }
    $search = New-Card @{ Dock = 'Left'; Width = (Px 300); Padding = (New-Padding 12 10 10 6) }
    $script:UI.SearchCard = $search
    if ($s.Icons) { $search.Controls.Add((New-Label ([string][char]0xE721) @{ Dock = 'Left'; Width = (Px 26); Font = $s.Icons; ForeColor = $s.TextDim; BackColor = $s.Card })) }
    $field = New-Control TextBox @{ Dock = 'Fill'; BorderStyle = 'None'; BackColor = $s.Card; ForeColor = $s.Text; Font = $s.Body }
    $search.Controls.Add($field); $field.BringToFront()
    $field.Add_TextChanged({ if ($script:Scanned) { Update-PlanPage } })
    $script:UI.Search = $field

    $filter = New-Segment @(@{ Id = 'all'; T = (L 'Wszystko' 'All') }, @{ Id = 'selected'; T = (L 'Zaznaczone' 'Selected') }, @{ Id = 'optin'; T = (L 'Na życzenie' 'Opt-in') }) { $script:PlanFilter } { param($id) $script:PlanFilter = $id; if ($script:Scanned) { Update-PlanPage } }
    $btnRecommended = New-Button (L 'Zaznacz zalecane' 'Select recommended') 'outline' @{ Dock = 'Right'; Width = (Px 160) }
    $btnClear = New-Button (L 'Odznacz wszystko' 'Clear selection') 'outline' @{ Dock = 'Right'; Width = (Px 150) }
    Add-Docked $bar @($search, (New-Spacer 'Left' 12), $filter, $btnClear, (New-Spacer 'Right' 10), $btnRecommended)
    $bar.Add_Resize({ if ($script:UI.SearchCard) { $script:UI.SearchCard.Width = [Math]::Max((Px 160), [Math]::Min((Px 320), $this.Width - $script:UI.PlanFilter.Width - $script:UI.BtnRecommended.Width - $script:UI.BtnClearSelection.Width - (Px 34))) } })
    $script:UI.BtnRecommended = $btnRecommended; $script:UI.BtnClearSelection = $btnClear; $script:UI.PlanFilter = $filter

    # List with a clickable column header (sorting)
    $k = New-Card @{ Dock = 'Fill'; Padding = (New-Padding 2 4 2 8) }
    $lv = New-RowList { param($g, $w, $r, $h) Draw-PlanRow $g $w $r $h }
    $col = New-Canvas @{ Dock = 'Top'; Height = (Px 34); BackColor = $s.Card; Cursor = [Windows.Forms.Cursors]::Hand } { param($g, $p) Draw-PlanColumns $g $p }
    $col.Add_MouseClick({ Set-PlanSort $_.X })
    # The box (left part of the row) ticks the item; the name shows its full description
    $lv.Tag.Click = {
        param($w, $x, $r)
        if ($x -ge (Get-PlanColumns $r.Width).Name) { return }
        if ($script:Working -or $script:Cleaned) { return }
        $o = $w.Obj
        if ($o.Blocker -and -not $o.Selected) { Set-WindowStatus $o.Blocker; return }
        $o.Selected = -not $o.Selected
        Update-PlanTotal
    }
    $lv.Tag.HintArea = { param($w, $x, $r) $x -ge (Get-PlanColumns $r.Width).Name }
    $lv.Tag.SectionClick = { param($w) $script:PlanExpanded[$w.Key] = [bool]$w.Collapsed; Update-PlanPage }
    $lv.Tag.Hint = { param($w) Get-PlanHint $w }
    $lv.Tag.DoubleClick = { param($w) $o = $w.Obj; if (-not $w.IsCategory -and (Test-GoesToRecycleBin $o) -and (Test-Path -LiteralPath $o.Path)) { Start-Process explorer.exe -ArgumentList "/select,`"$($o.Path)`"" } }
    $lv.Add_Resize({ if ($script:UI.PlanColumns) { $script:UI.PlanColumns.Invalidate() } })
    Add-Docked $k @($col, $lv)
    $script:UI.LvPlan = $lv; $script:UI.PlanColumns = $col

    # Action bar below the list
    $bottom = New-Card @{ Dock = 'Bottom'; Height = (Px 74); Padding = (New-Padding 20 14 14 14) }
    $btnClean = New-Button $(if ($Preview) { L 'Podgląd - czyszczenie wyłączone' 'Preview - cleaning disabled' } else { L 'Wyczyść zaznaczone...' 'Clean selected...' }) 'primary' @{ Dock = 'Right'; Width = (Px 220) }
    $btnExplain = New-Button (L 'AI: czym były pozostałości?' 'AI: what were the leftovers?') 'secondary' @{ Dock = 'Right'; Width = (Px 240) }
    $texts = New-Control Panel @{ Dock = 'Fill' }
    $total = New-Label '' @{ Dock = 'Top'; Height = (Px 26); Font = $s.Medium }
    $totalNote = New-Label '' @{ Dock = 'Fill'; ForeColor = $s.TextDim; Font = $s.Small; AutoEllipsis = $true }
    Add-Docked $texts @($total, $totalNote)
    Add-Docked $bottom @($btnClean, (New-Spacer 'Right' 10), $btnExplain, $texts)
    $script:UI.Total = $total; $script:UI.TotalNote = $totalNote; $script:UI.BtnClean = $btnClean; $script:UI.BtnExplain = $btnExplain

    Add-Docked $page @($n.Panel, $tabBar, (New-Spacer 'Top' 10), $bar, (New-Spacer 'Top' 14), $bottom, (New-Spacer 'Bottom' 14), $k)
    $page
}
