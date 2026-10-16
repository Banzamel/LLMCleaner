<#
    LLMCleaner - konto uzytkownika, ktorego profil jest sprzatany (takze gdy UAC podal haslo innego konta)
#>

# Na koncie standardowym UAC prosi o haslo innego konta (administratora) i skrypt dziala wtedy
# jako ono. Sprzatamy jednak profil osoby, ktora program uruchomila: jej foldery, rejestr i Kosz.
$mySid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$OtherUser = $false
if ($Sid -and $Sid -ne $mySid) {
    $sidProfile = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$Sid").ProfileImagePath
    if ($sidProfile -and (Test-Path -LiteralPath $sidProfile) -and (Test-Path "Registry::HKEY_USERS\$Sid")) {
        $OtherUser = $true
        $env:USERPROFILE = $sidProfile
    }
}
$UserSid = if ($OtherUser) { $Sid } else { $mySid }
$HKCUName = if ($OtherUser) { "HKEY_USERS\$Sid" } else { 'HKEY_CURRENT_USER' }
$HKCU = "Registry::$HKCUName"

# Folder powloki uzytkownika (moze byc przeniesiony, np. Dokumenty do OneDrive albo Pobrane na D:)
function Get-UserShellFolder([string]$name, [string]$fallback) {
    $v = (Get-ItemProperty "$HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders").$name
    if ($v) {
        $v = [Environment]::ExpandEnvironmentVariables($v.Replace('%USERPROFILE%', $env:USERPROFILE))
        if (Test-Path -LiteralPath $v) { return $v.TrimEnd('\') }
    }
    $fallback
}
if ($OtherUser) {
    $env:APPDATA = Get-UserShellFolder 'AppData' "$env:USERPROFILE\AppData\Roaming"
    $env:LOCALAPPDATA = Get-UserShellFolder 'Local AppData' "$env:USERPROFILE\AppData\Local"
    $env:TEMP = $env:TMP = "$env:LOCALAPPDATA\Temp"
}
