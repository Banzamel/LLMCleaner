<#
    LLMCleaner - window settings (window.json), light/dark theme, color palettes and fonts
#>

# window.json: size, position, last page and theme ("auto", "light" or "dark")
$script:WindowFile = Join-Path $env:LOCALAPPDATA 'LLMCleaner\window.json'
# Older versions saved okno.json with Polish keys and page ids
$oldWindowKeys = @{ Skala = 'Scale'; Strona = 'Page'; Motyw = 'Theme' }
$prefs = Read-PrefsFile $script:WindowFile (Join-Path $env:LOCALAPPDATA 'LLMCleaner\okno.json') $oldWindowKeys
$script:WindowPrefs = if ($prefs) { [pscustomobject]$prefs } else { $null }

function Test-DarkTheme {
    # The theme from the settings page takes precedence over the older field in window.json
    $m = if ($Config -and $Config.Theme) { "$($Config.Theme)" } else { "$($script:WindowPrefs.Theme)" }
    if ($m -eq 'dark') { return $true }
    if ($m -eq 'light') { return $false }
    (Get-ItemProperty "$HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize").AppsUseLightTheme -eq 0
}
$script:Dark = [bool](Test-DarkTheme)

$LightPalette = @{
    Background = '#F3F4F8'; Card = '#FFFFFF'; Tile = '#F6F7FB'; Border = '#E2E5EE'; ButtonBorder = '#D5D9E4'; Line = '#F0F1F5'
    Text = '#1F2333'; TextDim = '#5B6170'; Row = '#F8F9FC'
    Accent = '#2563EB'; AccentHover = '#1D4ED8'; AccentPressed = '#1E40AF'; AccentLight = '#EEF2FF'; AccentLightHover = '#E0E7FF'; AccentText = '#1D4ED8'
    Green = '#16A34A'; GreenHover = '#15803D'; Warning = '#B45309'; Red = '#B91C1C'; Ai = '#0F5E59'
    Track = '#EEF0F5'; GreyBar = '#A3A9B8'; Field = '#B8BDC9'; ToggleOff = '#B8BDC9'; TileProtected = '#6B7280'
    Disabled = '#E5E7EB'; TextDisabled = '#9CA3AF'; Segment = '#E6E8EF'; SegmentSelected = '#FFFFFF'
    NavBack = '#161A2B'; NavHover = '#222740'; NavSelectedBack = '#2B3254'; NavText = '#C3C8DA'; NavDim = '#A7AEC6'
    NoteBack = '#FFFBEB'; NoteBorder = '#FDE68A'; NoteText = '#78350F'
    SuccessBack = '#F0FDF4'; SuccessBorder = '#BBF7D0'; SuccessText = '#166534'
    OkBack = '#DCFCE7'; OkText = '#166534'; WarnBack = '#FEF3C7'; WarnText = '#92400E'; ErrorBack = '#FEE2E2'; ErrorText = '#991B1B'; NeutralBack = '#EEF0F5'; NeutralText = '#4B5160'
    PurpleBack = '#F3E8FF'; PurpleText = '#6B21A8'; BlueBack = '#E0F2FE'; BlueText = '#075985'
}
$DarkPalette = @{
    Background = '#0F1220'; Card = '#181C2C'; Tile = '#20253A'; Border = '#262B40'; ButtonBorder = '#343A55'; Line = '#20253A'
    Text = '#E6E8F0'; TextDim = '#A3A9BD'; Row = '#1D2133'
    Accent = '#3B82F6'; AccentHover = '#2563EB'; AccentPressed = '#1D4ED8'; AccentLight = '#1E2A4D'; AccentLightHover = '#25345F'; AccentText = '#BFD0FF'
    Green = '#22C55E'; GreenHover = '#16A34A'; Warning = '#F59E0B'; Red = '#EF4444'; Ai = '#5EEAD4'
    Track = '#2A3048'; GreyBar = '#4B5368'; Field = '#4B5368'; ToggleOff = '#3A4160'; TileProtected = '#4B5563'
    Disabled = '#2A3048'; TextDisabled = '#5B6378'; Segment = '#20253A'; SegmentSelected = '#2F3652'
    NavBack = '#0A0C17'; NavHover = '#151933'; NavSelectedBack = '#1E2440'; NavText = '#C3C8DA'; NavDim = '#A3A9BD'
    NoteBack = '#2A2410'; NoteBorder = '#4A3B12'; NoteText = '#FCD34D'
    SuccessBack = '#0F2A1C'; SuccessBorder = '#14532D'; SuccessText = '#86EFAC'
    OkBack = '#12301F'; OkText = '#86EFAC'; WarnBack = '#3A2E12'; WarnText = '#FCD34D'; ErrorBack = '#3A1618'; ErrorText = '#FCA5A5'; NeutralBack = '#2A3048'; NeutralText = '#A3A9BD'
    PurpleBack = '#2E1F45'; PurpleText = '#D8B4FE'; BlueBack = '#0C2A3A'; BlueText = '#7DD3FC'
}

$script:Style = @{}
$palette = if ($script:Dark) { $DarkPalette } else { $LightPalette }
foreach ($k in $palette.Keys) { $script:Style[$k] = ConvertTo-Color $palette[$k] }
$fonts = (New-Object Drawing.Text.InstalledFontCollection).Families.Name
# All window fonts are here (in points - Windows converts them to pixels by DPI)
$script:Style.Body = New-Object Drawing.Font('Segoe UI', 10)
$script:Style.Small = New-Object Drawing.Font('Segoe UI', 9.5)
$script:Style.SmallBold = New-Object Drawing.Font('Segoe UI Semibold', 9)
$script:Style.Badge = New-Object Drawing.Font('Segoe UI Semibold', 8)
$script:Style.Column = New-Object Drawing.Font('Segoe UI Semibold', 8.5)
$script:Style.Bold = New-Object Drawing.Font('Segoe UI Semibold', 10.5)
$script:Style.ButtonFont = New-Object Drawing.Font('Segoe UI Semibold', 10.5)
$script:Style.CardTitle = New-Object Drawing.Font('Segoe UI Semibold', 12)
$script:Style.Medium = New-Object Drawing.Font('Segoe UI Semibold', 13)
$script:Style.Number = New-Object Drawing.Font('Segoe UI Semibold', 16)
$script:Style.Logo = New-Object Drawing.Font('Segoe UI Semibold', 13)
$script:Style.Title = New-Object Drawing.Font('Segoe UI Semibold', 19)
$script:Style.Large = New-Object Drawing.Font('Segoe UI Semibold', 26)
$script:Style.Nav = New-Object Drawing.Font('Segoe UI', 10.5)
$script:Style.NavSelected = New-Object Drawing.Font('Segoe UI Semibold', 10.5)
$script:Style.Input = New-Object Drawing.Font('Segoe UI', 10.5)
$script:Style.Mono = New-Object Drawing.Font('Consolas', 9.5)
# Icons from the Windows 10/11 font; without it the navigation simply has no icons
if ($fonts -contains 'Segoe MDL2 Assets') {
    $script:Style.Icons = New-Object Drawing.Font('Segoe MDL2 Assets', 12)
    $script:Style.IconsSmall = New-Object Drawing.Font('Segoe MDL2 Assets', 8)
}

# Log line colors (console color names)
$LogColors = if ($script:Dark) {
    @{ Gray = ConvertTo-Color '#C9CDD8'; DarkGray = ConvertTo-Color '#7C8399'; White = ConvertTo-Color '#F3F4F8'; Green = ConvertTo-Color '#4ADE80'; Yellow = ConvertTo-Color '#FBBF24'
        Cyan = ConvertTo-Color '#93B4FF'; DarkCyan = ConvertTo-Color '#5EEAD4'; DarkYellow = ConvertTo-Color '#E0A458'
    }
}
else {
    @{ Gray = ConvertTo-Color '#374151'; DarkGray = ConvertTo-Color '#9CA3AF'; White = ConvertTo-Color '#111827'; Green = ConvertTo-Color '#16A34A'; Yellow = ConvertTo-Color '#B45309'
        Cyan = ConvertTo-Color '#2563EB'; DarkCyan = [Drawing.Color]::Teal; DarkYellow = [Drawing.Color]::Peru
    }
}

function Set-TaskbarProgress([int]$state, [double]$amount = 0, [double]$z = 1) {
    if ($script:UI.Window) { [LlmWin.Native]::TaskbarProgress($script:UI.Window.Handle, $state, [uint64]$amount, [uint64][Math]::Max(1.0, $z)) }
}
