# ============================================================
# Windows 11 23H2 → 25H2 Silent Upgrade Script
# PDQ Deploy Compatible
# Corrected OS version detection using DisplayVersion
# Verifies setup.exe actually starts
# Logs everything
# ============================================================

$ServerMedia = "\\MYSERVER\Sources\Win11_25H2"
$LocalMedia  = "C:\Windows\Temp\Win11_25H2_Upgrade"
$LogFile     = "C:\Windows\Temp\Win11_25H2_Upgrade.log"

Function Log {
    param([string]$Message)
    $ts = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "$ts | $Message"
    Write-Output "$Message"
}

Log "=== Starting Windows 11 25H2 Upgrade Script ==="

# ------------------------------------------
# Detect correct version from DisplayVersion
# ------------------------------------------
try {
    $DisplayVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
    Log "Detected Windows DisplayVersion: $DisplayVersion"
}
catch {
    Log "ERROR: Could not read DisplayVersion. Exiting."
    exit 1
}

# ------------------------------------------
# Determine if upgrade needed
# ------------------------------------------
if ($DisplayVersion -ge 25) {
    Log "System already running Windows 11 $DisplayVersion (25H2 or later). Exiting."
    exit 0
}

Log "System requires upgrade to 25H2. Proceeding..."

# ------------------------------------------
# Copy installation media locally
# ------------------------------------------
if (Test-Path $LocalMedia) {
    Log "Cleaning previous upgrade folder..."
    Remove-Item -Recurse -Force $LocalMedia
}

Log "Copying media from $ServerMedia to $LocalMedia ..."
Copy-Item -Recurse -Force $ServerMedia $LocalMedia

# ------------------------------------------
# Validate setup.exe
# ------------------------------------------
$Setup = "$LocalMedia\setup.exe"

if (!(Test-Path $Setup)) {
    Log "ERROR: setup.exe was NOT found at: $Setup"
    exit 1
}

Log "setup.exe found successfully."

# ------------------------------------------
# Run the silent upgrade
# ------------------------------------------
$Args = "/auto upgrade /quiet /dynamicupdate enable /compat ignorewarning /showoobe none /eula accept /telemetry disable /noreboot"

Log "Launching Windows Setup with arguments: $Args"

$Process = Start-Process -FilePath $Setup -ArgumentList $Args -PassThru

if (!$Process) {
    Log "ERROR: Failed to launch setup.exe"
    exit 1
}

Log "setup.exe started successfully. Waiting for exit..."

# Wait for setup.exe to finish (this may be very quick if preparation stage ends instantly)
Wait-Process -Id $Process.Id

# ------------------------------------------
# Check exit code
# ------------------------------------------
$ExitCode = $Process.ExitCode
Log "setup.exe exit code: $ExitCode"

# Known good exit codes:
# 0 = Success
# 3010 = Success, reboot required
# 1641 = Success, reboot initiated

if ($ExitCode -notin @(0, 3010, 1641)) {
    Log "ERROR: setup.exe returned a failure exit code ($ExitCode). Upgrade did NOT start."
    exit $ExitCode
}

Log "Setup completed successfully. A reboot will be initiated."

# ------------------------------------------
# Reboot to complete upgrade
# ------------------------------------------
shutdown.exe /r /t 30 /c "Completing upgrade to Windows 11 25H2..."

Log "=== Upgrade script has completed. System should reboot shortly. ==="

exit 0
