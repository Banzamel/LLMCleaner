<#
    LLMCleaner - the user account whose profile is cleaned (also when UAC got another account's password)
#>

# On a standard account UAC asks for another (administrator) account's password and the script then
# runs as that account. We still clean the profile of the person who started the program: their folders, registry and Recycle Bin.
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

# User shell folder (may be relocated, e.g. Documents to OneDrive or Downloads to D:)
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
