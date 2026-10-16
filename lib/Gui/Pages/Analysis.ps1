<#
    LLMCleaner - strona Analiza dysku
#>

function Draw-AnalysisRow($g, $w, $r, [bool]$hover) {
    if ($w.Section) { Draw-Section $g $w $r; return }
    $s = $script:Style; $p = $w.Obj
    Draw-RowBackground $g $r $hover
    $mid = $r.Y + [int]($r.Height / 2)
    Draw-Text $g (Format-Size $p.Bytes) $s.Bold $s.Text (Px 18) ($mid - (Px 12)) (Px 84) (Px 24) 'Right'
    $dateText = if ($p.LastWrite -gt [datetime]'1980-01-01') { $p.LastWrite.ToString('yyyy-MM-dd') } else { '' }
    Draw-Text $g $dateText $s.Small $s.TextDim (Px 118) ($mid - (Px 12)) (Px 90) (Px 24)
    $path = $p.Path
    if ($p.Remainder) { $path += L '  (pliki poza wymienionymi podfolderami)' '  (files outside the listed subfolders)' }
    $x = Px 214; $width = $r.Width - $x - (Px 18)
    Draw-Text $g $path $s.Body $s.Text $x ($mid - (Px 21)) $width (Px 21)
    if ($p.Ai) { Draw-Text $g "$AiLabel`: $($p.Ai)" $s.Small $s.Ai $x ($mid + (Px 1)) $width (Px 20) }
    elseif ($p.Hint) { Draw-Text $g $p.Hint $s.Small $s.TextDim $x ($mid + (Px 1)) $width (Px 20) }
}

function Update-AnalysisPage($a) {
    $rows = [System.Collections.Generic.List[object]]::new()
    if (@($a.Folders).Count) {
        $rows.Add(@{ Section = $true; H = (Px 40); Text = (L 'Największe foldery' 'Largest folders') })
        foreach ($p in $a.Folders) { $rows.Add(@{ H = (Px 54); Obj = $p }) }
    }
    if (@($a.Files).Count) {
        $rows.Add(@{ Section = $true; H = (Px 44); Text = (L 'Największe pliki' 'Largest files') })
        foreach ($p in $a.Files) { $rows.Add(@{ H = (Px 54); Obj = $p }) }
    }
    $script:UI.LvAnalysis.Tag.EmptyText = L 'Na tym dysku nie ma dużych folderów ani plików.' 'There are no large folders or files on this drive.'
    Set-Rows $script:UI.LvAnalysis $rows
    $script:UI.AnalysisData = $a
    $info = (L 'Dysk {0}: zajęte {1} z {2}, wolne {3}. Tylko do wglądu - nic stąd nie jest usuwane. Dwuklik otwiera folder.' 'Drive {0}: {1} used of {2}, {3} free. Read-only - nothing here is deleted. Double-click opens the folder.') -f
    $a.Letter, (Format-Size ($a.Size - $a.Free)), (Format-Size $a.Size), (Format-Size $a.Free)
    if ($a.ShadowCopies -gt 0) { $info += ' ' + ((L 'Punkty przywracania: {0}.' 'Restore points: {0}.') -f (Format-Size $a.ShadowCopies)) }
    $unreadable = ($a.Size - $a.Free) - $a.ScannedBytes - $a.ShadowCopies
    if ($unreadable -gt 2GB) { $info += ' ' + ((L 'Niedostępne dla skanera: ok. {0}.' 'Not readable by the scanner: about {0}.') -f (Format-Size $unreadable)) }
    $script:UI.AnalysisInfo.Text = $info
}

function New-AnalysisPage {
    $s = $script:Style
    $page = New-Page
    $n = New-PageHeader (L 'Co zajmuje miejsce' 'What takes up space') (L 'Szybki skan całego dysku (zwykle 30 s - 3 min). Pokazuje najbardziej konkretne duże foldery i największe pliki. Tylko do wglądu - nic stąd nie jest usuwane.' 'A fast scan of the whole drive (usually 30 s - 3 min). Shows the most specific large folders and the largest files. Read-only - nothing here is deleted.')
    $script:UI.AnalysisInfo = $n.Description

    $bar = New-Card @{ Dock = 'Top'; Height = (Px 70); Padding = (New-Padding 20 14 14 14) }
    $lbl = New-Label (L 'Dysk' 'Drive') @{ Dock = 'Left'; Width = (Px 56); Font = $s.Bold; TextAlign = 'MiddleLeft' }
    $cboPanel = New-Control Panel @{ Dock = 'Left'; Width = (Px 260); Padding = (New-Padding 0 8 0 0) }
    $cbo = New-Control ComboBox @{ DropDownStyle = 'DropDownList'; Dock = 'Top'; Font = $s.Body; FlatStyle = 'Flat'; BackColor = $s.Tile; ForeColor = $s.Text }
    $cboPanel.Controls.Add($cbo)
    $btnAnalyse = New-Button (L 'Analizuj' 'Analyse') 'primary' @{ Dock = 'Left'; Width = (Px 140) }
    $btnAnalyseAi = New-Button (L 'AI: opisz i doradź' 'AI: describe and advise') 'secondary' @{ Dock = 'Left'; Width = (Px 200) }
    Add-Docked $bar @($lbl, $cboPanel, (New-Spacer 'Left' 14), $btnAnalyse, (New-Spacer 'Left' 10), $btnAnalyseAi)
    $script:UI.CboDrive = $cbo; $script:UI.BtnAnalyse = $btnAnalyse; $script:UI.BtnAnalysisAi = $btnAnalyseAi

    $k = New-Card @{ Dock = 'Fill'; Padding = (New-Padding 2 4 2 8) }
    $lv = New-RowList { param($g, $w, $r, $h) Draw-AnalysisRow $g $w $r $h }
    $lv.Tag.EmptyText = L 'Wybierz dysk i kliknij „Analizuj”. Lista działa po skanie z Przeglądu.' 'Pick a drive and click "Analyse". The list works after a scan from Overview.'
    $lv.Tag.Click = { param($w, $x, $r) }
    $lv.Tag.HandCursor = { param($w, $x, $r) $false }
    $lv.Tag.DoubleClick = { param($w) if ($w.Obj.Path) { Start-Process explorer.exe -ArgumentList "/select,`"$($w.Obj.Path)`"" } }
    $lv.Tag.Hint = {
        param($w)
        $p = $w.Obj
        (@($p.Path, $p.Hint, $(if ($p.Ai) { "$AiLabel`: $($p.Ai)" })) | Where-Object { $_ }) -join "`n"
    }
    $k.Controls.Add($lv)
    $script:UI.LvAnalysis = $lv

    Add-Docked $page @($n.Panel, $bar, (New-Spacer 'Top' 14), $k)
    $page
}
