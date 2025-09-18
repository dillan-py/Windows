# Navigate to the key (create if missing)
$path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"

# Core Spectre/Meltdown mitigations (enables IBRS/IBPB/STIBP for CVE-2017-5715, CVE-2017-5753, CVE-2017-5754)
New-ItemProperty -Path $path -Name "FeatureSettingsOverride" -Value 0 -PropertyType DWord -Force
New-ItemProperty -Path $path -Name "FeatureSettingsOverrideMask" -Value 3 -PropertyType DWord -Force

# Speculative Store Bypass (CVE-2018-3639)
New-ItemProperty -Path $path -Name "SpeculationControl" -Value 1 -PropertyType DWord -Force

# L1TF (CVE-2018-3615, CVE-2018-3620, CVE-2018-3646)
New-ItemProperty -Path $path -Name "L1DataCachePolicy" -Value 2 -PropertyType DWord -Force

# MDS (CVE-2018-12126, CVE-2018-12127, CVE-2018-12130, CVE-2019-11091)
New-ItemProperty -Path $path -Name "MdsEnabled" -Value 1 -PropertyType DWord -Force

# TAA (CVE-2019-11135)
New-ItemProperty -Path $path -Name "TAAEnabled" -Value 1 -PropertyType DWord -Force

# BHI (CVE-2022-0001)
New-ItemProperty -Path $path -Name "BHIEnabled" -Value 1 -PropertyType DWord -Force
