# Copilot Instructions for CF_Install_REPO

## Overview

Repository containing **Azure Image Builder (AIB) installation scripts** and supporting resources for creating custom Windows images. Includes FSLogix configuration and Windows Sandbox experiments.

## Repository Structure

```
CF_Install_REPO/
├── AIB-Install-Scripts/    # Azure Image Builder customization scripts
├── FSLogix/                # FSLogix profile container configs
└── Sandbox/                # Windows Sandbox experiments
```

## AIB Script Patterns

### Standard Header
All AIB scripts require:
```powershell
<#
.SYNOPSIS
    AIB Customization: [Description]
.DESCRIPTION
    Script executed during Azure Image Builder customization phase
#>
```

### Write-Log Function
Standard logging for AIB troubleshooting:
```powershell
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path "C:\Windows\Temp\AIB-*.log" -Value "$timestamp - $Message"
}
```

### Key AIB Scripts

| Script | Purpose |
|--------|---------|
| `aib-extend-osdrive.ps1` | Extend OS drive partition |
| `aib-winget-install-apps.ps1` | Install applications via Winget |
| `aib-msi-exe-install-apps.ps1` | Install MSI/EXE packages |

### Winget Installation Pattern
For AIB (runs as SYSTEM):
```powershell
# Winget requires special handling in SYSTEM context
$wingetPath = Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__*\winget.exe" | 
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
& $wingetPath install --id "Package.Id" --silent --accept-package-agreements
```

## FSLogix Configuration

`FSLogix/downloadRedirections.xml.ps1`:
- Downloads FSLogix redirection XML templates
- Configures profile container exclusions

## Integration with Azure

These scripts are referenced in Azure Image Builder templates:
```json
{
    "type": "PowerShell",
    "name": "CustomizeStep",
    "scriptUri": "https://raw.githubusercontent.com/.../aib-script.ps1"
}
```

## Important Notes

- Scripts execute as SYSTEM during image build
- Log to `C:\Windows\Temp\` for AIB troubleshooting
- Test in Windows Sandbox before AIB deployment
