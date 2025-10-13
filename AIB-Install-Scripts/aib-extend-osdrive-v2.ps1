<# 
Extends the OS partition to consume all remaining unallocated space.
- Tries Storage module first (Resize-Partition).
- Falls back to diskpart if Storage path returns ObjectNotFound.
- Safe to re-run.
- Run as Administrator.

Usage:
  .\Expand-OSDisk-Robust.ps1                # defaults to OS drive (C:)
  .\Expand-OSDisk-Robust.ps1 -DriveLetter D
  .\Expand-OSDisk-Robust.ps1 -SuspendBitLocker
#>

[CmdletBinding()]
param(
  [ValidatePattern('^[A-Za-z]$')]
  [string]$DriveLetter = ($env:SystemDrive.TrimEnd(':','\')),
  [switch]$SuspendBitLocker
)

# Initialize logging
$logDirectory = 'C:\dvl-logs'
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

$logFile = Join-Path $logDirectory ("aib-extend-osdrive-v2_{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (-not (Test-Path -Path $logFile)) {
    New-Item -ItemType File -Path $logFile -Force | Out-Null
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message
    Add-Content -Path $logFile -Value $entry
    Write-Host $entry
}

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = [Security.Principal.WindowsPrincipal]$id
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Log -Message "Script must be run as Administrator." -Level 'ERROR'
    throw "Run this in an elevated PowerShell session (Run as Administrator)."
  }
  Write-Log -Message "Running with Administrator privileges."
}

function Get-TargetVolume {
  param([string]$Letter)

  $L = $Letter.TrimEnd(':','\').ToUpper()
  if ($L.Length -ne 1) { 
    Write-Log -Message "Invalid drive letter '$Letter'." -Level 'ERROR'
    throw "Invalid drive letter '$Letter'." 
  }

  Write-Log -Message "Searching for volume ${L}:..."

  # Prefer Get-Volume (it maps letters->Volume/Partition cleanly)
  $vol = Get-Volume -FileSystemLabel * -ErrorAction SilentlyContinue |
         Where-Object { $_.DriveLetter -and $_.DriveLetter.ToString().ToUpper() -eq $L } |
         Select-Object -First 1

  if (-not $vol) {
    # Fallback via WMI (very old/odd systems)
    $vol = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -eq $L } | Select-Object -First 1
  }
  if (-not $vol) { 
    Write-Log -Message "Volume ${L}: not found." -Level 'ERROR'
    throw "Volume ${L}: not found." 
  }
  Write-Log -Message "Found volume ${L}: (Size: $([math]::Round($vol.Size/1GB,2)) GB)"
  return $vol
}

function Try-Resize-With-Storage {
  param([char]$Letter)

  Write-Log -Message "Attempting resize using Storage module cmdlets..."

  # Ensure Storage cmdlets exist
  if (-not (Get-Command Get-Partition -ErrorAction SilentlyContinue)) {
    Write-Log -Message "Storage module not available." -Level 'WARN'
    throw [System.Management.Automation.CommandNotFoundException]::new("Storage module not available")
  }

  $part = Get-Partition -DriveLetter $Letter -ErrorAction Stop
  $disk = Get-Disk -Number $part.DiskNumber   -ErrorAction Stop

  Write-Log -Message "Located partition on Disk $($disk.Number): $($disk.FriendlyName), BusType: $($disk.BusType), PartitionStyle: $($disk.PartitionStyle)"

  if ($disk.IsOffline)  { 
    Write-Log -Message "Disk $($disk.Number) is offline; bringing online..." -Level 'WARN'
    Set-Disk -Number $disk.Number -IsOffline:$false -ErrorAction Stop 
  }
  if ($disk.IsReadOnly) { 
    Write-Log -Message "Disk $($disk.Number) is read-only; clearing read-only flag..." -Level 'WARN'
    Set-Disk -Number $disk.Number -IsReadOnly:$false -ErrorAction Stop 
  }

  Update-HostStorageCache | Out-Null
  Write-Log -Message "Storage cache updated."

  $supported = $null
  try {
    Write-Log -Message "Getting supported size for Partition $($part.PartitionNumber) on Disk $($part.DiskNumber)..."
    $supported = Get-PartitionSupportedSize -DiskNumber $part.DiskNumber -PartitionNumber $part.PartitionNumber -ErrorAction Stop
  } catch {
    # Sometimes DriveLetter works when PartitionNumber path glitches
    Write-Log -Message "Failed with DiskNumber/PartitionNumber method. Trying DriveLetter method..." -Level 'WARN'
    $supported = Get-PartitionSupportedSize -DriveLetter $Letter -ErrorAction Stop
  }

  if ($null -eq $supported -or $supported.SizeMax -le $part.Size) {
    $currentGB = [math]::Round($part.Size/1GB,2)
    Write-Log -Message "No unallocated space after ${Letter}:. Already at maximum ($currentGB GB)." -Level 'INFO'
    Write-Output "No unallocated space after ${Letter}:. Already at maximum ($currentGB GB)."
    return $true  # nothing to do, but not an error
  }

  $beforeGB = [math]::Round($part.Size/1GB,2)
  $targetGB = [math]::Round($supported.SizeMax/1GB,2)
  Write-Log -Message "Extending ${Letter}: from $beforeGB GB to $targetGB GB using Storage module..."
  Write-Output "Extending ${Letter}: via Storage from $beforeGB GB to $targetGB GB ..."
  Resize-Partition -DriveLetter $Letter -Size $supported.SizeMax -ErrorAction Stop

  $final = Get-Partition -DriveLetter $Letter
  $finalGB = [math]::Round($final.Size/1GB,2)
  Write-Log -Message "Extension successful. ${Letter}: is now $finalGB GB." -Level 'SUCCESS'
  Write-Output "Done. ${Letter}: is now $finalGB GB."
  return $true
}

function Try-Resize-With-DiskPart {
  param([char]$Letter)

  Write-Log -Message "Attempting resize using diskpart..." -Level 'WARN'

  # Check if diskpart can see free space by querying size before/after
  $before = (Get-Volume -DriveLetter $Letter).SizeRemaining

  $dp = @"
select volume $Letter
extend
exit
"@
  $temp = New-TemporaryFile
  try {
    Set-Content -Path $temp -Value $dp -Encoding ASCII
    Write-Log -Message "Executing diskpart extend on volume ${Letter}:..."
    Write-Output "Attempting diskpart extend on volume ${Letter}: ..."
    $proc = Start-Process -FilePath diskpart.exe -ArgumentList "/s `"$temp`"" -Wait -PassThru -WindowStyle Hidden
    if ($proc.ExitCode -ne 0) { 
      Write-Log -Message "diskpart exited with code $($proc.ExitCode)" -Level 'ERROR'
      throw "diskpart exited with code $($proc.ExitCode)" 
    }
    Write-Log -Message "diskpart completed successfully."
  } finally {
    Remove-Item $temp -ErrorAction SilentlyContinue
  }

  # Quick verification
  Start-Sleep -Seconds 1
  $after = (Get-Volume -DriveLetter $Letter).SizeRemaining
  if ($after -lt $before) {
    Write-Log -Message "diskpart: Extension appears successful." -Level 'SUCCESS'
    Write-Output "diskpart: Extension appears successful."
    return $true
  } else {
    # Could still be ok if volume had little free space before; re-check partition size:
    $p = Get-Partition -DriveLetter $Letter -ErrorAction SilentlyContinue
    if ($p) {
      $sizeGB = [math]::Round($p.Size/1GB,2)
      Write-Log -Message "Current partition size: $sizeGB GB"
      Write-Output ("Current partition size: {0} GB" -f $sizeGB)
    }
    return $true  # don't fail the run if diskpart succeeded silently
  }
}

try {
  Write-Log -Message "Starting OS drive extension script."
  Assert-Admin

  $DriveLetter = $DriveLetter.TrimEnd(':','\').ToUpper()
  Write-Log -Message "Target drive letter: ${DriveLetter}:"
  $vol = Get-TargetVolume -Letter $DriveLetter
  $letterChar = [char]$DriveLetter

  if ($SuspendBitLocker) {
    try {
      Write-Log -Message "Checking BitLocker status on ${DriveLetter}:..."
      $bl = Get-BitLockerVolume -MountPoint "${DriveLetter}:\\" -ErrorAction Stop
      if ($bl.ProtectionStatus -eq 'On') {
        Write-Log -Message "Suspending BitLocker on ${DriveLetter}: for one reboot..." -Level 'WARN'
        Write-Output "Suspending BitLocker on ${DriveLetter}: for one reboot..."
        Suspend-BitLocker -MountPoint "${DriveLetter}:\\" -RebootCount 1 -ErrorAction Stop
      }
    } catch { 
      Write-Log -Message "BitLocker not present or not enabled on ${DriveLetter}: ($($_.Exception.Message))"
      Write-Verbose "BitLocker not present or not enabled on ${DriveLetter}: ($($_.Exception.Message))" 
    }
  }
  
  $done = $false
  try {
    $done = Try-Resize-With-Storage -Letter $letterChar
  } catch {
    if ($_.CategoryInfo.Category -eq 'ObjectNotFound') {
      Write-Log -Message "Storage module returned ObjectNotFound. Falling back to diskpart..." -Level 'WARN'
      Write-Warning "Storage path returned ObjectNotFound. Falling back to diskpart..."
      $done = Try-Resize-With-DiskPart -Letter $letterChar
    } else {
      Write-Log -Message $_.Exception.Message -Level 'ERROR'
      throw
    }
  }

  if (-not $done) { 
    Write-Log -Message "Unable to extend the partition." -Level 'ERROR'
    throw "Unable to extend the partition." 
  }

  Write-Log -Message "Script execution completed successfully." -Level 'SUCCESS'

} catch {
  Write-Log -Message $_.Exception.Message -Level 'ERROR'
  Write-Error $_.Exception.Message
  exit 1
}