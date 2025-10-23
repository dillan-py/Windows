#requires -RunAsAdministrator
#requires -Version 5.1

<#
.SYNOPSIS
    Configures TLS on a Windows print server by disabling TLS 1.0/1.1, enabling TLS 1.2/1.3, and managing print services.

.DESCRIPTION
    This script:
    - Backs up the SCHANNEL registry.
    - Disables TLS 1.0 and 1.1, enables TLS 1.2 and 1.3.
    - Configures secure cipher suites.
    - Enables SCHANNEL logging for troubleshooting.
    - Restarts Print Spooler and LPD Service (if present) with robust status checking.
    - Logs all actions to C:\Logs\TLS_Configuration_Log.txt.
    - Handles LPD Service startup issues and provides fallback if not needed.

.NOTES
    - Must be run as Administrator.
    - Test in a non-production environment first.
    - Fixed variable parsing issues with ${} for all Write-Log calls.
    - Optimized for Windows Server 2016/2019/2022.
    - Date: October 23, 2025
#>

# Set up logging
$LogPath = "C:\Logs\TLS_Configuration_Log.txt"
$Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
if (-not (Test-Path -Path "C:\Logs")) {
    New-Item -ItemType Directory -Path "C:\Logs" -Force | Out-Null
}
Add-Content -Path $LogPath -Value "[$Date] Starting TLS configuration script..."

# Function to log messages
function Write-Log {
    param ($Message)
    $Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "[$Date] $Message"
}

# Function to restart a service with robust status checking
function Restart-ServiceWithRetry {
    param (
        [string]$ServiceName,
        [int]$MaxRetries = 3,
        [int]$TimeoutSeconds = 90  # Increased timeout for reliability
    )
    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        try {
            Write-Log "Attempting to restart service ${ServiceName} (Attempt $($retryCount + 1)/$MaxRetries)"
            $service = Get-Service -Name $ServiceName -ErrorAction Stop
            Write-Log "Current status of ${ServiceName}: $($service.Status)"

            # Stop the service if running or starting
            if ($service.Status -eq 'Running' -or $service.Status -eq 'Starting') {
                Stop-Service -Name $ServiceName -Force -ErrorAction Stop
                Write-Log "Stopped ${ServiceName}"
                Start-Sleep -Seconds 5
            }

            # Start the service
            Start-Service -Name $ServiceName -ErrorAction Stop
            $timeout = (Get-Date).AddSeconds($TimeoutSeconds)
            while ($service.Status -ne 'Running' -and (Get-Date) -lt $timeout) {
                Write-Log "Waiting for ${ServiceName} to start (Current status: $($service.Status))..."
                Start-Sleep -Seconds 5
                $service.Refresh()
            }

            if ($service.Status -eq 'Running') {
                Write-Log "${ServiceName} restarted successfully."
                return $true
            } else {
                throw "Service ${ServiceName} failed to start within $TimeoutSeconds seconds. Current status: $($service.Status)"
            }
        } catch {
            Write-Log "ERROR: Failed to restart ${ServiceName}: $_"
            $retryCount++
            if ($retryCount -eq $MaxRetries) {
                Write-Log "ERROR: Max retries reached for ${ServiceName}."
                if ($ServiceName -eq "LPDSVC") {
                    Write-Log "WARNING: LPD Service failed to start. Continuing as it may not be critical."
                    return $true  # Fallback to continue if LPDSVC fails
                }
                return $false
            }
            Start-Sleep -Seconds 10
        }
    }
}

# Check if running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "ERROR: Script must be run as Administrator."
    Write-Error "This script requires administrative privileges. Please run as Administrator."
    exit 1
}

# Backup the registry
$BackupPath = "C:\Logs\SCHANNEL_Backup_$((Get-Date).ToString('yyyyMMdd_HHmmss')).reg"
try {
    Write-Log "Backing up SCHANNEL registry to $BackupPath"
    reg export "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL" $BackupPath
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Registry backup successful."
    } else {
        throw "Registry backup failed."
    }
} catch {
    Write-Log "ERROR: Failed to backup registry: $_"
    Write-Error "Failed to backup registry. Aborting script."
    exit 1
}

# Define registry paths
$SchannelPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
$Protocols = @("TLS 1.0", "TLS 1.1", "TLS 1.2", "TLS 1.3")
$SubKeys = @("Client", "Server")

# Configure TLS protocols
foreach ($Protocol in $Protocols) {
    $ProtocolPath = "$SchannelPath\$Protocol"
    
    foreach ($SubKey in $SubKeys) {
        $FullPath = "$ProtocolPath\$SubKey"
        
        try {
            if (-not (Test-Path $FullPath)) {
                New-Item -Path $FullPath -Force | Out-Null
                Write-Log "Created registry path: ${FullPath}"
            }

            if ($Protocol -eq "TLS 1.0" -or $Protocol -eq "TLS 1.1") {
                Set-ItemProperty -Path $FullPath -Name "Enabled" -Value 0 -Type DWORD -Force
                Set-ItemProperty -Path $FullPath -Name "DisabledByDefault" -Value 1 -Type DWORD -Force
                Write-Log "Disabled $Protocol for $SubKey"
            } else {
                Set-ItemProperty -Path $FullPath -Name "Enabled" -Value 1 -Type DWORD -Force
                Set-ItemProperty -Path $FullPath -Name "DisabledByDefault" -Value 0 -Type DWORD -Force
                Write-Log "Enabled $Protocol for $SubKey"
            }
        } catch {
            Write-Log "ERROR: Failed to configure ${FullPath}: $_"
            Write-Warning "Failed to configure ${FullPath}. Check permissions or registry access."
        }
    }
}

# Enable SCHANNEL logging
$SchannelRoot = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL"
try {
    Set-ItemProperty -Path $SchannelRoot -Name "EventLogging" -Value 1 -Type DWORD -Force
    Write-Log "Enabled SCHANNEL logging (EventLogging = 1)"
} catch {
    Write-Log "ERROR: Failed to enable SCHANNEL logging: $_"
    Write-Warning "Failed to enable SCHANNEL logging."
}

# Configure secure cipher suites
$SecureCiphers = @(
    "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
    "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
    "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
    "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
)

try {
    foreach ($Cipher in $SecureCiphers) {
        Enable-TlsCipherSuite -Name $Cipher -ErrorAction Stop
        Write-Log "Enabled cipher suite: $Cipher"
    }
    $WeakCiphers = @("TLS_RSA_WITH_3DES_EDE_CBC_SHA")
    foreach ($Cipher in $WeakCiphers) {
        Disable-TlsCipherSuite -Name $Cipher -ErrorAction SilentlyContinue
        Write-Log "Disabled weak cipher: $Cipher"
    }
} catch {
    Write-Log "ERROR: Failed to configure cipher suites: $_"
    Write-Warning "Failed to configure cipher suites. Manual configuration may be required."
}

# Ensure TCP 515 is open for LPD Service
try {
    $rule = Get-NetFirewallRule -Name "Allow_LPD_515" -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -Name "Allow_LPD_515" -DisplayName "Allow LPD Service (TCP 515)" -Direction Inbound -Protocol TCP -LocalPort 515 -Action Allow
        Write-Log "Created firewall rule for LPD Service (TCP 515)"
    } else {
        Write-Log "Firewall rule for LPD Service (TCP 515) already exists"
    }
} catch {
    Write-Log "ERROR: Failed to configure firewall rule for LPD Service: $_"
    Write-Warning "Failed to configure firewall rule for LPD Service."
}

# Check LPD Service dependencies
try {
    $lpdService = Get-Service -Name "LPDSVC" -ErrorAction SilentlyContinue
    if ($lpdService) {
        $dependencies = $lpdService | Select-Object -ExpandProperty ServicesDependedOn
        foreach ($dep in $dependencies) {
            $depStatus = Get-Service -Name $dep.Name
            Write-Log "Dependency ${dep.Name}: $($depStatus.Status)"
            if ($depStatus.Status -ne 'Running') {
                Write-Log "Starting dependency ${dep.Name}"
                Start-Service -Name $dep.Name -ErrorAction Stop
            }
        }
    } else {
        Write-Log "LPD Service (LPDSVC) not installed on this system."
    }
} catch {
    Write-Log "ERROR: Failed to check/start LPD Service dependencies: $_"
}

# Restart Print Spooler and LPD Service
$services = @("Spooler", "LPDSVC")
foreach ($service in $services) {
    if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
        if (-not (Restart-ServiceWithRetry -ServiceName $service)) {
            Write-Log "ERROR: Failed to restart ${service} after $MaxRetries attempts."
            Write-Warning "Failed to restart ${service}. Manual intervention may be required."
        }
    } else {
        Write-Log "Service ${service} not found on this system."
    }
}

# Verify TLS configuration
try {
    $CurrentProtocols = [Net.ServicePointManager]::SecurityProtocol
    Write-Log "Current security protocols: $CurrentProtocols"
    Write-Host "Current security protocols: $CurrentProtocols"
} catch {
    Write-Log "ERROR: Failed to verify security protocols: $_"
    Write-Warning "Unable to verify current security protocols."
}

# Additional diagnostics for LPD Service
try {
    $lpdService = Get-Service -Name "LPDSVC" -ErrorAction SilentlyContinue
    if ($lpdService) {
        Write-Log "Final LPD Service status: $($lpdService.Status)"
        Write-Host "Final LPD Service status: $($lpdService.Status)"
        $portTest = Test-NetConnection -ComputerName localhost -Port 515
        Write-Log "TCP 515 connectivity test: TcpTestSucceeded = $($portTest.TcpTestSucceeded)"
        Write-Host "TCP 515 connectivity test: TcpTestSucceeded = $($portTest.TcpTestSucceeded)"
    } else {
        Write-Log "LPD Service not installed, skipping diagnostics."
    }
} catch {
    Write-Log "ERROR: Failed to perform LPD Service diagnostics: $_"
}

# Final log message
Write-Log "TLS configuration script completed."
Write-Host "TLS configuration completed. Check log at $LogPath for details."

# Instructions for further verification
Write-Host "Next steps:"
Write-Host "- Verify TLS settings: 'nmap --script ssl-enum-ciphers -p 443 <server_ip>'"
Write-Host "- Check Event Viewer (System logs) for SCHANNEL or LPDSVC errors."
Write-Host "- Ensure clients/printers support TLS 1.2/1.3."
Write-Host "- If LPD Service is not needed: 'Set-Service -Name LPDSVC -StartupType Disabled'"
Write-Host "- If issues persist, provide log ($LogPath) and Event Viewer errors."
