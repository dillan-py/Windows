# ============================================================
# Windows 11 23H2 → 25H2 Silent Upgrade Script
# Automatically detects edition, validates ISO, PDQ Deploy ready
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

# -----------------------------
# Stage 1: Detect Windows version
# -----------------------------
Log "=== Stage 1: Detecting Windows version ==="
try {
    $DisplayVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion
    Log "Detected Windows DisplayVersion: $DisplayVersion"
}
catch {
    Log "ERROR: Could not read DisplayVersion. Exiting."
    exit 1
}

if ($DisplayVersion -eq "25H2") {
    Log "System already running Windows 11 25H2. Exiting."
    exit 0
}
Log "Upgrade required: Windows 11 $DisplayVersion → 25H2"

# -----------------------------
# Stage 2: Detect installed edition
# -----------------------------
Log "=== Stage 2: Detecting installed edition ==="
try {
    $EditionID = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID
    Log "Installed EditionID: $EditionID"
}
catch {
    Log "ERROR: Could not detect installed EditionID."
    exit 1
}

# -----------------------------
# Stage 3: Copy installation media locally
# -----------------------------
Log "=== Stage 3: Copying installation media locally ==="
if (Test-Path $LocalMedia) {
    Log "Cleaning previous upgrade folder..."
    Remove-Item -Recurse -Force $LocalMedia
}

try {
    Log "Copying media from $ServerMedia to $LocalMedia ..."
    Copy-Item -Recurse -Force $ServerMedia $LocalMedia
    Log "Media copied successfully"
}
catch {
    Log "ERROR: Failed to copy installation media. Exiting."
    exit 1
}

# -----------------------------
# Stage 4: Validate setup.exe and install.wim
# -----------------------------
Log "=== Stage 4: Validating setup.exe and install.wim ==="
$Setup = "$LocalMedia\setup.exe"
$WimFile = "$LocalMedia\sources\install.wim"

if (!(Test-Path $Setup)) {
    Log "ERROR: setup.exe not found at $Setup"
    exit 1
}

if (!(Test-Path $WimFile)) {
    Log "ERROR: install.wim not found at $WimFile"
    exit 1
}

# -----------------------------
# Stage 5: Detect WIM index automatically
# -----------------------------
Log "=== Stage 5: Detecting WIM index for installed edition ==="
try {
    $WimInfo = dism /Get-WimInfo /WimFile:$WimFile 2>&1
    $IndexMapping = @{}

    # Map DISM Index names to index numbers
    foreach ($line in $WimInfo) {
        if ($line -match "Index : (\d+)") { $currentIndex = [int]$matches[1] }
        if ($line -match "Name : (.+)") { $name = $matches[1].Trim(); $IndexMapping[$name] = $currentIndex }
    }

    # Pre-flight mapping: EditionID → WIM Name
    $EditionToWimName = @{
        "Core"                     = "Windows 11 Home"
        "CoreN"                    = "Windows 11 Home N"
        "CoreSingleLanguage"       = "Windows 11 Home Single Language"
        "Education"                = "Windows 11 Education"
        "EducationN"               = "Windows 11 Education N"
        "Professional"             = "Windows 11 Pro"
        "ProfessionalN"            = "Windows 11 Pro N"
        "ProfessionalEducation"    = "Windows 11 Pro Education"
        "ProfessionalEducationN"   = "Windows 11 Pro Education N"
        "ProWorkstations"          = "Windows 11 Pro for Workstations"
        "ProWorkstationsN"         = "Windows 11 Pro N for Workstations"
    }

    if (-not $EditionToWimName.ContainsKey($EditionID)) {
        Log "ERROR: Unsupported EditionID: $EditionID. Cannot continue."
        exit 1
    }

    $ExpectedWimName = $EditionToWimName[$EditionID]

    if (-not $IndexMapping.ContainsKey($ExpectedWimName)) {
        Log "ERROR: ISO does not contain WIM image for $EditionID ($ExpectedWimName)"
        exit 1
    }

    $WimIndex = $IndexMapping[$ExpectedWimName]
    Log "Detected WIM index $WimIndex for EditionID $EditionID ($ExpectedWimName)"
}
catch {
    Log "ERROR: Failed to parse WIM info or detect correct index."
    exit 1
}

# -----------------------------
# Stage 6: Launch Setup.exe
# -----------------------------
Log "=== Stage 6: Launching Setup.exe ==="
$Args = "/auto upgrade /quiet /eula accept /dynamicupdate enable /compat ignorewarning /showoobe none /telemetry disable /noreboot /installfrom `"$WimFile`:$WimIndex`""
Log "Running: $Setup $Args"

try {
    $Process = Start-Process -FilePath $Setup -ArgumentList $Args -PassThru
    if (!$Process) {
        Log "ERROR: Failed to launch setup.exe"
        exit 1
    }
    Log "setup.exe started successfully"
}
catch {
    Log "ERROR: Exception occurred while launching setup.exe"
    exit 1
}

# -----------------------------
# Stage 7: Wait for Setup.exe to exit with heartbeat
# -----------------------------
Log "=== Stage 7: Waiting for Setup.exe to complete ==="
$HeartbeatSeconds = 60
while (-not $Process.HasExited) {
    Log "setup.exe running... waiting for exit"
    Start-Sleep -Seconds $HeartbeatSeconds
    $Process.Refresh()
}

$ExitCode = $Process.ExitCode
Log "setup.exe exit code: $ExitCode"

if ($ExitCode -notin @(0, 3010, 1641)) {
    Log "ERROR: setup.exe returned failure exit code ($ExitCode). Upgrade did NOT complete."
    exit $ExitCode
}

Log "Setup staged successfully. Upgrade will complete on reboot."

# -----------------------------
# Stage 8: Reboot to complete upgrade
# -----------------------------
Log "=== Stage 8: Rebooting to finalize upgrade ==="
shutdown.exe /r /t 30 /c "Completing upgrade to Windows 11 25H2..."
Log "=== Upgrade script completed. System will reboot ==="

exit 0
