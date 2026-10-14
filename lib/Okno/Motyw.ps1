<#
    LLMCleaner - ustawienia okna (okno.json), motyw jasny/ciemny, palety kolorow i czcionki
#>

# okno.json: rozmiar, polozenie, ostatnia strona i motyw ("auto", "jasny" albo "ciemny")
$script:OknoPlik = Join-Path $env:LOCALAPPDATA 'LLMCleaner\okno.json'
$script:Ustawienia = $null
if (Test-Path -LiteralPath $script:OknoPlik) {
    try { $script:Ustawienia = Get-Content -LiteralPath $script:OknoPlik -Raw | ConvertFrom-Json } catch { $script:Ustawienia = $null }
}

function MotywCiemny {
    $m = "$($script:Ustawienia.Motyw)"
    if ($m -in 'ciemny', 'dark') { return $true }
    if ($m -in 'jasny', 'light') { return $false }
    (Get-ItemProperty "$HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize").AppsUseLightTheme -eq 0
}
$script:Ciemny = [bool](MotywCiemny)

$PaletaJasna = @{
    Tlo = '#F3F4F8'; Karta = '#FFFFFF'; Kafelek = '#F6F7FB'; Ramka = '#E2E5EE'; RamkaPrzycisku = '#D5D9E4'; Linia = '#F0F1F5'
    Tekst = '#1F2333'; TekstSlaby = '#5B6170'; Wiersz = '#F8F9FC'
    Akcent = '#2563EB'; AkcentHover = '#1D4ED8'; AkcentWcisniety = '#1E40AF'; AkcentJasny = '#EEF2FF'; AkcentJasnyHover = '#E0E7FF'; AkcentTekst = '#1D4ED8'
    Zielony = '#16A34A'; ZielonyHover = '#15803D'; Ostrzezenie = '#B45309'; Czerwony = '#B91C1C'; Ai = '#0F5E59'
    Tor = '#EEF0F5'; SzaryPasek = '#A3A9B8'; Pole = '#B8BDC9'; PrzelacznikWyl = '#B8BDC9'; KafelekChroniony = '#6B7280'
    Wylaczony = '#E5E7EB'; TekstWylaczony = '#9CA3AF'; Segment = '#E6E8EF'; SegmentWybrany = '#FFFFFF'
    Nawigacja = '#161A2B'; NawHover = '#222740'; NawWybrany = '#2B3254'; NawTekst = '#C3C8DA'; NawSlaby = '#A7AEC6'
    NotkaTlo = '#FFFBEB'; NotkaRamka = '#FDE68A'; NotkaTekst = '#78350F'
    SukcesTlo = '#F0FDF4'; SukcesRamka = '#BBF7D0'; SukcesTekst = '#166534'
    OkTlo = '#DCFCE7'; OkTekst = '#166534'; UwagaTlo = '#FEF3C7'; UwagaTekst = '#92400E'; BladTlo = '#FEE2E2'; BladTekst = '#991B1B'; NeutralTlo = '#EEF0F5'; NeutralTekst = '#4B5160'
    FioletTlo = '#F3E8FF'; FioletTekst = '#6B21A8'; BlekitTlo = '#E0F2FE'; BlekitTekst = '#075985'
}
$PaletaCiemna = @{
    Tlo = '#0F1220'; Karta = '#181C2C'; Kafelek = '#20253A'; Ramka = '#262B40'; RamkaPrzycisku = '#343A55'; Linia = '#20253A'
    Tekst = '#E6E8F0'; TekstSlaby = '#A3A9BD'; Wiersz = '#1D2133'
    Akcent = '#3B82F6'; AkcentHover = '#2563EB'; AkcentWcisniety = '#1D4ED8'; AkcentJasny = '#1E2A4D'; AkcentJasnyHover = '#25345F'; AkcentTekst = '#BFD0FF'
    Zielony = '#22C55E'; ZielonyHover = '#16A34A'; Ostrzezenie = '#F59E0B'; Czerwony = '#EF4444'; Ai = '#5EEAD4'
    Tor = '#2A3048'; SzaryPasek = '#4B5368'; Pole = '#4B5368'; PrzelacznikWyl = '#3A4160'; KafelekChroniony = '#4B5563'
    Wylaczony = '#2A3048'; TekstWylaczony = '#5B6378'; Segment = '#20253A'; SegmentWybrany = '#2F3652'
    Nawigacja = '#0A0C17'; NawHover = '#151933'; NawWybrany = '#1E2440'; NawTekst = '#C3C8DA'; NawSlaby = '#A3A9BD'
    NotkaTlo = '#2A2410'; NotkaRamka = '#4A3B12'; NotkaTekst = '#FCD34D'
    SukcesTlo = '#0F2A1C'; SukcesRamka = '#14532D'; SukcesTekst = '#86EFAC'
    OkTlo = '#12301F'; OkTekst = '#86EFAC'; UwagaTlo = '#3A2E12'; UwagaTekst = '#FCD34D'; BladTlo = '#3A1618'; BladTekst = '#FCA5A5'; NeutralTlo = '#2A3048'; NeutralTekst = '#A3A9BD'
    FioletTlo = '#2E1F45'; FioletTekst = '#D8B4FE'; BlekitTlo = '#0C2A3A'; BlekitTekst = '#7DD3FC'
}

$script:Styl = @{}
$paleta = if ($script:Ciemny) { $PaletaCiemna } else { $PaletaJasna }
foreach ($k in $paleta.Keys) { $script:Styl[$k] = Kolor $paleta[$k] }
$czcionki = (New-Object Drawing.Text.InstalledFontCollection).Families.Name
# Wszystkie czcionki okna sa tutaj (w punktach - Windows przelicza je na piksele wedlug DPI)
$script:Styl.Czcionka = New-Object Drawing.Font('Segoe UI', 10)
$script:Styl.Mala = New-Object Drawing.Font('Segoe UI', 9.5)
$script:Styl.MalaPogr = New-Object Drawing.Font('Segoe UI Semibold', 9)
$script:Styl.Odznaka = New-Object Drawing.Font('Segoe UI Semibold', 8)
$script:Styl.Kolumna = New-Object Drawing.Font('Segoe UI Semibold', 8.5)
$script:Styl.Pogrubiona = New-Object Drawing.Font('Segoe UI Semibold', 10.5)
$script:Styl.Przycisk = New-Object Drawing.Font('Segoe UI Semibold', 10.5)
$script:Styl.TytulKarty = New-Object Drawing.Font('Segoe UI Semibold', 12)
$script:Styl.Srednia = New-Object Drawing.Font('Segoe UI Semibold', 13)
$script:Styl.Liczba = New-Object Drawing.Font('Segoe UI Semibold', 16)
$script:Styl.Logo = New-Object Drawing.Font('Segoe UI Semibold', 13)
$script:Styl.Tytul = New-Object Drawing.Font('Segoe UI Semibold', 19)
$script:Styl.Duza = New-Object Drawing.Font('Segoe UI Semibold', 26)
$script:Styl.Nav = New-Object Drawing.Font('Segoe UI', 10.5)
$script:Styl.NavWybrany = New-Object Drawing.Font('Segoe UI Semibold', 10.5)
$script:Styl.PoleTekstu = New-Object Drawing.Font('Segoe UI', 10.5)
$script:Styl.Mono = New-Object Drawing.Font('Consolas', 9.5)
# Ikony z czcionki Windows 10/11; bez niej nawigacja jest po prostu bez ikon
if ($czcionki -contains 'Segoe MDL2 Assets') {
    $script:Styl.Ikony = New-Object Drawing.Font('Segoe MDL2 Assets', 12)
    $script:Styl.IkonyMale = New-Object Drawing.Font('Segoe MDL2 Assets', 8)
}

# Kolory linii logu (nazwy kolorow konsoli)
$KoloryOkna = if ($script:Ciemny) {
    @{ Gray = Kolor '#C9CDD8'; DarkGray = Kolor '#7C8399'; White = Kolor '#F3F4F8'; Green = Kolor '#4ADE80'; Yellow = Kolor '#FBBF24'
        Cyan = Kolor '#93B4FF'; DarkCyan = Kolor '#5EEAD4'; DarkYellow = Kolor '#E0A458'
    }
}
else {
    @{ Gray = Kolor '#374151'; DarkGray = Kolor '#9CA3AF'; White = Kolor '#111827'; Green = Kolor '#16A34A'; Yellow = Kolor '#B45309'
        Cyan = Kolor '#2563EB'; DarkCyan = [Drawing.Color]::Teal; DarkYellow = [Drawing.Color]::Peru
    }
}

function PostepNaPasku([int]$stan, [double]$ile = 0, [double]$z = 1) {
    if ($script:UI.Okno) { [LlmWin.Natywne]::PostepNaPasku($script:UI.Okno.Handle, $stan, [uint64]$ile, [uint64][Math]::Max(1.0, $z)) }
}
