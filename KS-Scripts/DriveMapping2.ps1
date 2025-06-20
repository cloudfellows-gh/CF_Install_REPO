# Set up logging
$logDir = "C:\DVL-Logs"
$logFile = "$logDir\DriveMapping.log"

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "$timestamp - $Message"
}

Write-Log "=== Starting drive mapping ==="

# Define drive mappings
$drives = @(
    @{ DriveLetter = 'I:'; Path = '\\ks-app-inf01.keij-stefels.local\Informant' },
    @{ DriveLetter = 'X:'; Path = '\\ks-app-inf01.keij-stefels.local\I_Beheer' },
    @{ DriveLetter = 'B:'; Path = '\\ks-app-inf01.keij-stefels.local\I_Administratie' }
)

foreach ($drive in $drives) {
    $letter = $drive.DriveLetter
    $path = $drive.Path

    Write-Log "Mapping $letter to $path..."

    try {
        # Disconnect if already mapped
        net use $letter /delete /y > $null 2>&1

        # Map the drive
        $result = net use $letter $path /persistent:yes 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "SUCCESS: $letter mapped to $path"
        } else {
            Write-Log "FAILED: $letter could not be mapped. Output: $result"
        }
    } catch {
        Write-Log "EXCEPTION mapping $letter: $_"
    }
}

Write-Log "=== Drive mapping complete ==="
