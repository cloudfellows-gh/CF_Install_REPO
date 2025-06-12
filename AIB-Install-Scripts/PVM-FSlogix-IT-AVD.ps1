$VhdLocations = "\\iwvbprweuwvdp.file.core.windows.net\weuuserprofile-it"
$RegistryPath = "HKLM:\Software\FSLogix\Profiles"

If (-NOT (Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
}
New-ItemProperty -Path $RegistryPath -Name "Enabled" -Value 1 -PropertyType DWORD -Force
New-ItemProperty -Path $RegistryPath -Name "DeleteLocalProfileWhenVHDShouldApply" -Value 1 -PropertyType DWORD -Force
New-ItemProperty -Path $RegistryPath -Name "PreventLoginWithFailure" -Value 1 -PropertyType DWORD -Force
New-ItemProperty -Path $RegistryPath -Name "PreventLoginWithTempProfile" -Value 1 -PropertyType DWORD -Force
New-ItemProperty -Path $RegistryPath -Name "FlipFlopProfileDirectoryName" -Value 1 -PropertyType DWORD -Force
New-ItemProperty -Path $RegistryPath -Name "KeepLocalDir" -Value 1 -PropertyType DWORD -Force
New-ItemProperty -Path $RegistryPath -Name "VolumeType" -Value VHDX -PropertyType STRING -Force
New-ItemProperty -Path $RegistryPath -Name "VHDLocations" -Value $VhdLocations -PropertyType MultiString -Force

# Registry FSlogix variable Apps
$RegistryPathApps = "HKLM:\SOFTWARE\FSLogix\Apps"

# Create registry keys
If (-NOT (Test-Path $RegistryPathApps)) {
    New-Item -Path $RegistryPathApps -Force | Out-Null
}
New-ItemProperty -Path $RegistryPathApps -Name "CleanupInvalidSessions" -Value 1 -PropertyType DWORD -Force