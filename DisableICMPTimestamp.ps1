# Script to disable ICMP Timestamp Responses by modifying the Windows Registry
# Run this script with administrative privileges

# Log file path for tracking script execution
$logFile = "C:\Logs\DisableICMPTimestamp.log"
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
$regKey = "EnableICMPRedirect"
$regValue = 0

# Ensure the script is running with administrative privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Error: This script requires administrative privileges. Please run as Administrator." -ForegroundColor Red
    exit 1
}

# Create logs directory if it doesn't exist
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Function to write to log file
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append
}

# Log script start
Write-Log "Starting script to disable ICMP Timestamp Responses."

try {
    # Check if the registry path exists
    if (-not (Test-Path $regPath)) {
        Write-Host "Error: Registry path $regPath does not exist." -ForegroundColor Red
        Write-Log "Error: Registry path $regPath does not exist."
        exit 1
    }

    # Check if the EnableICMPRedirect key exists
    $keyExists = Get-ItemProperty -Path $regPath -Name $regKey -ErrorAction SilentlyContinue
    if ($keyExists) {
        # Update existing key
        Set-ItemProperty -Path $regPath -Name $regKey -Value $regValue
        Write-Host "Updated $regKey to $regValue in $regPath." -ForegroundColor Green
        Write-Log "Updated $regKey to $regValue in $regPath."
    } else {
        # Create new key
        New-ItemProperty -Path $regPath -Name $regKey -Value $regValue -PropertyType DWORD -Force | Out-Null
        Write-Host "Created $regKey with value $regValue in $regPath." -ForegroundColor Green
        Write-Log "Created $regKey with value $regValue in $regPath."
    }

    # Optionally, set DisableIPSourceRouting (additional security measure)
    $sourceRoutingKey = "DisableIPSourceRouting"
    $sourceRoutingValue = 2
    $sourceRoutingExists = Get-ItemProperty -Path $regPath -Name $sourceRoutingKey -ErrorAction SilentlyContinue
    if ($sourceRoutingExists) {
        Set-ItemProperty -Path $regPath -Name $sourceRoutingKey -Value $sourceRoutingValue
        Write-Host "Updated $sourceRoutingKey to $sourceRoutingValue in $regPath." -ForegroundColor Green
        Write-Log "Updated $sourceRoutingKey to $sourceRoutingValue in $regPath."
    } else {
        New-ItemProperty -Path $regPath -Name $sourceRoutingKey -Value $sourceRoutingValue -PropertyType DWORD -Force | Out-Null
        Write-Host "Created $sourceRoutingKey with value $sourceRoutingValue in $regPath." -ForegroundColor Green
        Write-Log "Created $sourceRoutingKey with value $sourceRoutingValue in $regPath."
    }

    # Prompt for system restart
    Write-Host "A system restart is required to apply the changes." -ForegroundColor Yellow
    $restart = Read-Host "Would you like to restart now? (Y/N)"
    if ($restart -eq 'Y' -or $restart -eq 'y') {
        Write-Log "Initiating system restart."
        Restart-Computer -Force
    } else {
        Write-Host "Please restart the system manually to apply the changes." -ForegroundColor Yellow
        Write-Log "User chose not to restart. Manual restart required."
    }
}
catch {
    Write-Host "Error: An unexpected error occurred: $_" -ForegroundColor Red
    Write-Log "Error: An unexpected error occurred: $_"
    exit 1
}

# Log script completion
Write-Log "Script completed successfully."
Write-Host "Script completed. Check the log file at $logFile for details." -ForegroundColor Green
