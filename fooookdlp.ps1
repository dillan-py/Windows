# ================================================
# Windows 11 23H2 → 25H2 Silent In-Place Upgrade
# Fully unattended | PDQ Deploy Compatible
# ================================================

$ServerMedia = "\\YOURSERVER\Sources\Win11_25H2"
$LocalMedia  = "C:\_Win11_25H2"
$LogFile     = "C:\Windows\Temp\Win11_25H2_Upgrade.log"

Function Log {
    param([string]$msg)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "$timestamp | $msg"
    Write-Output $msg
}

Log "=== Windows 11 25H2 Upgrade Script Starting ==="

# --- Detect Release ID ---
try {
    $ReleaseID = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId
    Log "Detected Windows Release: $ReleaseID"
} catch {
    Log "ERROR: Cannot read Release ID."
    exit 1
}

# --- Check if Upgrade Needed ---
if ($ReleaseID -ge 2500) {
    Log "System already running 25H2 or newer. Exiting."
    exit 0
}

Log "Upgrade required. Continuing..."

# --- Copy Media from Server ---
if (Test-Path $LocalMedia) {
    Log "Removing existing local media..."
    Remove-Item -Recurse -Force $LocalMedia
}

Log "Copying Windows 11 25H2 installation media..."
Copy-Item -Recurse -Force $ServerMedia $LocalMedia

$Setup = "$LocalMedia\setup.exe"

if (!(Test-Path $Setup)) {
    Log "ERROR: setup.exe not found at: $Setup"
    exit 1
}

Log "Launching Windows 11 Setup..."

# --- Silent Upgrade Arguments ---
$Args = "/auto upgrade /quiet /dynamicupdate enable /compat ignorewarning /showoobe none /eula accept /telemetry disable /restart"

Start-Process -FilePath $Setup -ArgumentList $Args -Wait

Log "Setup process complete. System will reboot shortly."

# --- In case setup doesn't reboot automatically ---
shutdown.exe /r /t 30 /c "Upgrading Windows 11 to version 25H2..."

Log "=== Upgrade Script Completed ==="
exit 0
