# Install required applications using WinGet in SYSTEM context
# Assumes WinGet is already available (included in Windows 11 23H2 images)

# Ensure WinGet is available
$wingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
if (-Not (Test-Path $wingetPath)) {
    Write-Host "WinGet is not available. Exiting." -ForegroundColor Red
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
    Write-Host "Installing $packageId..." -ForegroundColor Cyan

    try {
        Start-Process -FilePath $wingetPath -ArgumentList "install --id $packageId --silent --accept-package-agreements --accept-source-agreements --scope machine" -Wait -NoNewWindow
        Write-Host "$packageId installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to install $packageId" -ForegroundColor Red
    }
}

Write-Host "All installations attempted." -ForegroundColor Yellow

# Get the C: partition
$cDrive = Get-Partition -DriveLetter C

# Get the disk that holds the C: partition
$disk = Get-Disk | Where-Object { $_.Number -eq $cDrive.DiskNumber }

# Check for unallocated space
$unallocated = ($disk | Get-PartitionSupportedSize -PartitionNumber $cDrive.PartitionNumber)

if ($unallocated.SizeMax -gt $cDrive.Size) {
    # Extend the C: drive to use all available space
    Resize-Partition -DriveLetter C -Size $unallocated.SizeMax
    Write-Host "C: drive successfully extended to use all unallocated space."
} else {
    Write-Host "No unallocated space found on the disk for the C: drive."
}
$groupName = "FSLogix Profile Exclude List"
$userToAdd = "cfuser1815"

# Check if group exists, create if it doesn't
if (-not (Get-LocalGroup -Name $groupName -ErrorAction SilentlyContinue)) {
    New-LocalGroup -Name $groupName -Description "Users excluded from FSLogix profile management"
    Write-Host "Created local group '$groupName'"
} else {
    Write-Host "Local group '$groupName' already exists"
}

# Check if user is in group
$groupMembers = Get-LocalGroupMember -Group $groupName | Select-Object -ExpandProperty Name
if ($groupMembers -notcontains $userToAdd) {
    Add-LocalGroupMember -Group $groupName -Member $userToAdd
    Write-Host "Added '$userToAdd' to group '$groupName'"
} else {
    Write-Host "'$userToAdd' is already a member of group '$groupName'"
}
