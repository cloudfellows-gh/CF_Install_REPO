
# === CONFIGURATION ===
$ScriptPath = "$env:SystemDrive\Install\fslogix\"
$LogFolder = "C:\DVL-Logs"
$LogFile = "$LogFolder\Redirections.xml.log"
$Destination = "$env:SystemDrive\Install\fslogix\Redirections.xml"

# === LOGGING FUNCTION ===
function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $Message"
    Add-Content -Path $LogFile -Value $entry
}

# === INITIALIZE LOGGING ===
if (!(Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}
Write-Log "=== Script started ==="

# === Ensure local folder exists ===
$ScriptFolder = Split-Path $ScriptPath
if (!(Test-Path $ScriptFolder)) {
    New-Item -ItemType Directory -Path $ScriptFolder -Force | Out-Null
    Write-Log "Created local script folder at $ScriptFolder"
}

# URL of the raw file from GitHub
$Url = "https://raw.githubusercontent.com/<username>/<repository>/<branch>/Redirections.xml"


# Ensure destination directory exists
$Directory = Split-Path $Destination
if (!(Test-Path $Directory)) {
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
}

# Download the file
Invoke-WebRequest -Uri $Url -OutFile $Destination

Write-Host "File downloaded to $Destination"