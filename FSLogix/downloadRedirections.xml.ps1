# === CONFIGURATION ===
$ScriptPath = "$env:SystemDrive\Install\fslogix\"
$LogFolder  = "C:\DVL-Logs"
$LogFile    = Join-Path $LogFolder "Redirections.xml.log"
$Destination = Join-Path $ScriptPath "Redirections.xml"

# Registry key config
$RegPath = "HKLM:\SOFTWARE\FSLogix\Profiles"
$RegName = "RedirXMLSourceFolder"
$RegValue = "C:\Install\fslogix"

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

# === Ensure local script folder exists ===
if (!(Test-Path $ScriptPath)) {
    New-Item -ItemType Directory -Path $ScriptPath -Force | Out-Null
    Write-Log "Created local folder $ScriptPath"
} else {
    Write-Log "Local folder already exists: $ScriptPath"
}

# === File source URL (fixed branch) ===
$Url = "https://raw.githubusercontent.com/cloudfellows-gh/CF_Install_REPO/main/FSLogix/Redirections.xml"

# === Ensure destination directory exists ===
$DestinationDir = Split-Path $Destination
if (!(Test-Path $DestinationDir)) {
    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    Write-Log "Created destination directory $DestinationDir"
} else {
    Write-Log "Destination directory exists: $DestinationDir"
}

# === Download the file ===
try {
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
    Write-Log "File downloaded to $Destination"
} catch {
    Write-Log "ERROR: Failed to download file: $($_.Exception.Message)"
    throw
}

# === Registry update ===
try {
    if (!(Test-Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
        Write-Log "Created registry path: $RegPath"
    }
    New-ItemProperty -Path $RegPath -Name $RegName -Value $RegValue -PropertyType String -Force | Out-Null
    Write-Log "Registry value set: $RegPath\$RegName = $RegValue"
} catch {
    Write-Log "ERROR: Failed to update registry: $($_.Exception.Message)"
    throw
}

Write-Log "=== Script finished ==="