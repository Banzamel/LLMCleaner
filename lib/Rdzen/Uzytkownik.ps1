<#
    LLMCleaner - konto uzytkownika, ktorego profil jest sprzatany (takze gdy UAC podal haslo innego konta)
#>

# Na koncie standardowym UAC prosi o haslo innego konta (administratora) i skrypt dziala wtedy
# jako ono. Sprzatamy jednak profil osoby, ktora program uruchomila: jej foldery, rejestr i Kosz.
$mojSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$InnyUzytkownik = $false
if ($Sid -and $Sid -ne $mojSid) {
    $profilSid = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$Sid").ProfileImagePath
    if ($profilSid -and (Test-Path -LiteralPath $profilSid) -and (Test-Path "Registry::HKEY_USERS\$Sid")) {
        $InnyUzytkownik = $true
        $env:USERPROFILE = $profilSid
    }
}
$UzytkownikSid = if ($InnyUzytkownik) { $Sid } else { $mojSid }
$HKCUNazwa = if ($InnyUzytkownik) { "HKEY_USERS\$Sid" } else { 'HKEY_CURRENT_USER' }
$HKCU = "Registry::$HKCUNazwa"

# Folder powloki uzytkownika (moze byc przeniesiony, np. Dokumenty do OneDrive albo Pobrane na D:)
function FolderUzytkownika([string]$nazwa, [string]$domyslny) {
    $v = (Get-ItemProperty "$HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders").$nazwa
    if ($v) {
        $v = [Environment]::ExpandEnvironmentVariables($v.Replace('%USERPROFILE%', $env:USERPROFILE))
        if (Test-Path -LiteralPath $v) { return $v.TrimEnd('\') }
    }
    $domyslny
}
if ($InnyUzytkownik) {
    $env:APPDATA = FolderUzytkownika 'AppData' "$env:USERPROFILE\AppData\Roaming"
    $env:LOCALAPPDATA = FolderUzytkownika 'Local AppData' "$env:USERPROFILE\AppData\Local"
    $env:TEMP = $env:TMP = "$env:LOCALAPPDATA\Temp"
}
