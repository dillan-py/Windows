# ============================================================
# Windows 11 23H2 → 25H2 Silent Upgrade Script
# PDQ Deploy Compatible
# Features:
# - Detects installed Windows edition
# - Maps edition to correct WIM index
# - Validates local ISO/extracted media
# - Runs silent upgrade with forced reboot
# - Logs everything
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
# Detect Windows version (DisplayVersion)
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
# Determine if upgrade is needed
# ------------------------------------------
if ($DisplayVersion -ge 25) {
    Log "System already running Windows 11 $DisplayVersion (25H2 or later). Exiting."
    exit 0
}

Log "System requires upgrade to 25H2. Proceeding..."

# ------------------------------------------
# Detect installed edition
# ------------------------------------------
try {
    $EditionID = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID
    Log "Installed Edition: $EditionID"
}
catch {
    Log "ERROR: Could not detect installed EditionID."
    exit 1
}

# ------------------------------------------
# Map installed edition to WIM index
# ------------------------------------------
$WimIndex = switch ($EditionID) {
    "Core"                     { 1 }
    "CoreN"                    { 2 }
    "CoreSingleLanguage"       { 3 }
    "Education"                { 4 }
    "EducationN"               { 5 }
    "Professional"             { 6 }
    "ProfessionalN"            { 7 }
    "ProfessionalEducation"    { 8 }
    "ProfessionalEducationN"   { 9 }
    "ProWorkstations"          { 10 }
    "ProWorkstationsN"         { 11 }
    default {
        Log "ERROR: Unsupported EditionID: $EditionID. Upgrade cannot continue."
        exit 1
    }
}

Log "Mapped EditionID $EditionID to install.wim index $WimIndex"

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
# Validate setup.exe and install.wim
# ------------------------------------------
$Setup = "$LocalMedia\setup.exe"
$WimFile = "$LocalMedia\sources\install.wim"

if (!(Test-Path $Setup)) {
    Log "ERROR: setup.exe was NOT found at: $Setup"
    exit 1
}

if (!(Test-Path $WimFile)) {
    Log "ERROR: install.wim was NOT found at: $WimFile"
    exit 1
}

# Validate that WIM index exists
try {
    $WimInfo = dism /Get-WimInfo /WimFile:$WimFile 2>&1
    $ValidIndexes = ($WimInfo | Where-Object {$_ -match "Index : (\d+)"} | ForEach-Object {$matches[1]})
    if ($ValidIndexes -notcontains $WimIndex) {
        Log "ERROR: WIM index $WimIndex for Edition $EditionID not found in $WimFile"
        exit 1
    }
    Log "Validated WIM index $WimIndex exists in install.wim"
}
catch {
    Log "ERROR: Could not read WIM info from $WimFile"
    exit 1
}

Log "setup.exe and install.wim validated successfully."

# ------------------------------------------
# Run the silent upgrade
# ------------------------------------------
$Args = "/auto upgrade /quiet /eula accept /dynamicupdate enable /compat ignorewarning /showoobe none /telemetry disable /noreboot /installfrom `"$WimFile`:$WimIndex`""

Log "Launching Windows Setup with arguments: $Args"

$Process = Start-Process -FilePath $Setup -ArgumentList $Args -PassThru

if (!$Process) {
    Log "ERROR: Failed to launch setup.exe"
    exit 1
}

Log "setup.exe started successfully. Waiting for exit..."

Wait-Process -Id $Process.Id

# ------------------------------------------
# Check exit code
# ------------------------------------------
$ExitCode = $Process.ExitCode
Log "setup.exe exit code: $ExitCode"

if ($ExitCode -notin @(0, 3010, 1641)) {
    Log "ERROR: setup.exe returned a failure exit code ($ExitCode). Upgrade did NOT start."
    exit $ExitCode
}

Log "Setup completed successfully. A reboot will be initiated."

# ------------------------------------------
# Reboot to complete upgrade
# ------------------------------------------
shutdown.exe /r /t 30 /c "Completing upgrade to Windows 11 25H2..."

Log "=== Upgrade script has completed. System will reboot ==="

exit 0
