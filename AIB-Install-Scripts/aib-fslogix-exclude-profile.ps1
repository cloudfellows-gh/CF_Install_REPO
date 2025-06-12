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
