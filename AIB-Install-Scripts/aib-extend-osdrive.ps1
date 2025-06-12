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
