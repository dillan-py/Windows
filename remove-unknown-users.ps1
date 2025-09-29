# PowerShell script to remove "Account Unknown" user profiles
# Run as Administrator
 
# Get all user profiles except system ones
$profiles = Get-WmiObject Win32_UserProfile | Where-Object {
    ($_.LocalPath -notlike "*systemprofile*") -and
    ($_.LocalPath -notlike "*NetworkService*") -and
    ($_.LocalPath -notlike "*LocalService*")
}
 
foreach ($profile in $profiles) {
    try {
        $sid = New-Object System.Security.Principal.SecurityIdentifier($profile.SID)
        $account = $sid.Translate([System.Security.Principal.NTAccount])
    }
    catch {
        $account = $null
    }
 
    # If no account is found, it's an orphan profile ("Account Unknown")
    if (-not $account) {
        Write-Host "Deleting Account Unknown profile: $($profile.LocalPath)"
        $profile.Delete()
    }
}
