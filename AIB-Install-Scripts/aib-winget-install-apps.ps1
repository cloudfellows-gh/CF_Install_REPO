
$ErrorActionPreference = 'SilentlyContinue'

# Initialize Logging
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Upgrade_To_Win11_24H2.log"         
Function Write-Log {
    Param([string]$Message)
    "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - $Message" | Out-File -FilePath $LogPath  -Append
}
Write-Log "====================== Upgrading Windows 10 to Windows 11 24H2 Using Intune Proactive Detection Script $(Get-Date -Format 'yyyy/MM/dd') ==================="

# Install required applications using WinGet in SYSTEM context
# Assumes WinGet is already available (included in Windows 11 23H2 images)

# Ensure WinGet is available
$wingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
if (-Not (Test-Path $wingetPath)) {
    Write-Log "WinGet is not available. Exiting." -ForegroundColor Red
    exit 1
}

# Applications to install
$apps = @(
    @{ name = "7zip.7zip"; },
    @{ name = "Adobe.Acrobat.Reader.64-bit"; },
    @{ name = "Microsoft.VCRedist.2015+.x86"; },
    @{ name = "Microsoft.VCRedist.2015+.x64"; },
    @{ name = "Google.Chrome"; },
    @{ name = "Microsoft.Powershell"; },
    @{ name = "VideoLAN.VLC"; }
)

# Loop through each app and install
foreach ($app in $apps) {
    $packageId = $app.name
    Write-Log "Installing $packageId..." -ForegroundColor Cyan

    try {
        Start-Process -FilePath $wingetPath -ArgumentList "install --id $packageId --silent --accept-package-agreements --accept-source-agreements --scope machine" -Wait -NoNewWindow
        Write-Log "$packageId installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Log "Failed to install $packageId" -ForegroundColor Red
    }
}

Write-Log "All installations attempted." -ForegroundColor Yellow

############################################
# Get the C: partition
############################################
$cDrive = Get-Partition -DriveLetter C

# Get the disk that holds the C: partition
$disk = Get-Disk | Where-Object { $_.Number -eq $cDrive.DiskNumber }

# Check for unallocated space
$unallocated = ($disk | Get-PartitionSupportedSize -PartitionNumber $cDrive.PartitionNumber)

if ($unallocated.SizeMax -gt $cDrive.Size) {
    # Extend the C: drive to use all available space
    Resize-Partition -DriveLetter C -Size $unallocated.SizeMax
    Write-Log "C: drive successfully extended to use all unallocated space."
} else {
    Write-Log "No unallocated space found on the disk for the C: drive."
}

##############################################################
# Add user to local administrators group
# This script creates a local user account and adds it to the Administrators group.
# It checks if the user already exists before attempting to create it.
# The user is created with a secure password and the account is set to never expire.
##############################################################
# Set username and password
$username = "CFuser1815"
$passwordPlain = "7*2nzLH&u3E@GQ!sp5L5!3y7wW9E#3Bp"

# Convert plain password to secure string
$password = ConvertTo-SecureString $passwordPlain -AsPlainText -Force

# Check if the user already exists
if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
    Write-Host "User '$username' already exists. Skipping account creation." -ForegroundColor Yellow
} else {
    # Create the local user account
    New-LocalUser -Name $username -Password $password -FullName "CFuser1815" -Description "Local admin account for VDI" -PasswordNeverExpires
    Write-Host "User '$username' created successfully." -ForegroundColor Green

    # Add the user to the Administrators group
    Add-LocalGroupMember -Group "Administrators" -Member $username
    Write-Host "User '$username' added to the Administrators group." -ForegroundColor Green
}


##############################################################
# Add user to local group for FSLogix profile exclusion
##############################################################
$groupName = "FSLogix Profile Exclude List"
$userToAdd = "cfuser1815"

# Check if group exists, create if it doesn't
if (-not (Get-LocalGroup -Name $groupName -ErrorAction SilentlyContinue)) {
    New-LocalGroup -Name $groupName -Description "Users excluded from FSLogix profile management"
    Write-Log "Created local group '$groupName'"
} else {
    Write-Log "Local group '$groupName' already exists"
}

# Check if user is in group
$groupMembers = Get-LocalGroupMember -Group $groupName | Select-Object -ExpandProperty Name
if ($groupMembers -notcontains $userToAdd) {
    Add-LocalGroupMember -Group $groupName -Member $userToAdd
    Write-Log "Added '$userToAdd' to group '$groupName'"
} else {
    Write-Log "'$userToAdd' is already a member of group '$groupName'"
}
