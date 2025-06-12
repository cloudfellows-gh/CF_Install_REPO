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
