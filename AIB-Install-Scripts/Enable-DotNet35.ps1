<#
.SYNOPSIS
    Enable .NET Framework 3.5 Windows Feature

.DESCRIPTION
    This script enables the .NET Framework 3.5 Windows feature on Windows systems.
    Requires administrative privileges to run.

.EXAMPLE
    .\Enable-DotNet35.ps1
    Enables .NET Framework 3.5 feature

.NOTES
    Author: CloudFellows
    Date: 28-10-2025
#>

#Requires -RunAsAdministrator

# Check if running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

try {
    Write-Host "Checking current status of .NET Framework 3.5..." -ForegroundColor Cyan
    
    # Check if feature is already enabled
    $feature = Get-WindowsOptionalFeature -Online -FeatureName NetFx3
    
    if ($feature.State -eq "Enabled") {
        Write-Host ".NET Framework 3.5 is already enabled" -ForegroundColor Green
        exit 0
    }
    
    Write-Host "Enabling .NET Framework 3.5..." -ForegroundColor Yellow
    Write-Host "This may take several minutes and may require internet connectivity..." -ForegroundColor Yellow
    
    # Enable the feature
    $result = Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart
    
    if ($result.RestartNeeded) {
        Write-Host ".NET Framework 3.5 has been enabled successfully" -ForegroundColor Green
        Write-Warning "A system restart is required to complete the installation"
        
        $restart = Read-Host "Would you like to restart now? (Y/N)"
        if ($restart -eq 'Y' -or $restart -eq 'y') {
            Write-Host "Restarting computer..." -ForegroundColor Yellow
            Restart-Computer -Force
        } else {
            Write-Host "Please restart your computer manually to complete the installation" -ForegroundColor Yellow
        }
    } else {
        Write-Host ".NET Framework 3.5 has been enabled successfully" -ForegroundColor Green
        Write-Host "No restart required" -ForegroundColor Green
    }
    
} catch {
    Write-Error "Failed to enable .NET Framework 3.5: $_"
    Write-Host "`nTroubleshooting tips:" -ForegroundColor Yellow
    Write-Host "- Ensure you have internet connectivity" -ForegroundColor Yellow
    Write-Host "- Check Windows Update is functioning properly" -ForegroundColor Yellow
    Write-Host "- You may need to specify an alternate source using DISM" -ForegroundColor Yellow
    exit 1
}
