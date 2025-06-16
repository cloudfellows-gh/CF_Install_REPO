# Some organizations, use non-persistent virtual machines for their users
# A non-persistent machine is created from a master image
# Every new machine instance has a different name and these machines are available via pool
# Every user logon \ reboot returns machine to image state loosing all user data
# This script provides a solution for onboarding such machines
# We would like to have sense unique id per machine name in organization
# For that purpose, senseGuid is set prior to onboarding
# The guid is created deterministically based on combination of orgId and machine name 
# This script is intended to be integrated in golden image startup
Param (	
	[string]
	[ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Path $_ -PathType ‘Container’})]
	$onboardingPackageLocation = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
)

Add-Type @'
using System; 
using System.Diagnostics; 
using System.Diagnostics.Tracing; 
namespace Sense 
{ 
	[EventData(Name = "Onboard")]
	public struct Onboard
	{
		public string Message { get; set; }
	} 
	public class Trace 
	{
		public static EventSourceOptions TelemetryCriticalOption = new EventSourceOptions(){Level = EventLevel.Informational, Keywords = (EventKeywords)0x0000800000000000, Tags = (EventTags)0x0200000}; 
		public void WriteMessage(string message)
		{
			es.Write("OnboardNonPersistentMachine", TelemetryCriticalOption, new Onboard {Message = message});
		} 
		private static readonly string[] telemetryTraits = { "ETW_GROUP", "{5ECB0BAC-B930-47F5-A8A4-E8253529EDB7}" }; 
		private EventSource es = new EventSource("Microsoft.Windows.Sense.Client.VDI",EventSourceSettings.EtwSelfDescribingEventFormat,telemetryTraits);
	}
}
'@

$logger = New-Object -TypeName Sense.Trace;
$logFilePath = Join-Path -Path $env:windir -ChildPath "temp\VDIlog.txt"

function EnsureLogFileExists {

    $logFolder = Join-Path -Path $env:windir -ChildPath "temp"

    if (-not (Test-Path -Path $logFolder -PathType Container)) {
        $null = New-Item -Path $logFolder -ItemType Directory
    }

    if (-not (Test-Path -Path $logFilePath)) {
        $null = New-Item -Path $logFilePath -ItemType File
    }
}


function Trace([string] $message)
{
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "`r`n$timestamp - $message"

    # Append log message to the log file
    EnsureLogFileExists
    Add-Content -Path $logFilePath -Value $logMessage

    $logger.WriteMessage($message)

}

function CreateGuidFromString([string]$str)
{
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($str)
    $sha1CryptoServiceProvider = New-Object System.Security.Cryptography.SHA1CryptoServiceProvider
    $hashedBytes = $sha1CryptoServiceProvider.ComputeHash($bytes)
    [System.Array]::Resize([ref]$hashedBytes, 16);
    return New-Object System.Guid -ArgumentList @(,$hashedBytes)
}

function GetComputerName 
{
    return [system.environment]::MachineName
}

function ReadOrgIdFromOnboardingScript($onboardingScript)
{
    return select-string -path $onboardingScript -pattern "orgId\\\\\\`":\\\\\\`"([^\\]+)" | %{ $_.Matches[0].Groups[1].Value }
}

function Test-Administrator  
{  
    $user = [Security.Principal.WindowsIdentity]::GetCurrent();
    return (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)  
}

if ((Test-Administrator) -eq $false)
{
    Write-Host -ForegroundColor Red "The script should be executed with admin previliges"
    Trace("Script wasn't executed as admin");
    Exit 1;
}

Write-Host "Locating onboarding script under:" $onboardingPackageLocation

$onboardingScript = [System.IO.Path]::Combine($onboardingPackageLocation, "WindowsDefenderATPOnboardingScript.cmd");

if(![System.IO.File]::Exists($onboardingScript))
{
    Write-Host -ForegroundColor Red "Onboarding script not found:" $onboardingScript
    Trace("Default Onboarding script not found")
    $onboardingScript = [System.IO.Path]::Combine($onboardingPackageLocation, "DeviceComplianceOnboardingScript.cmd");
    if(![System.IO.File]::Exists($onboardingScript)) 
    {
        Write-Host -ForegroundColor Red "Onboarding script not found:" $onboardingScript
        Trace("Compliance Onboarding script not found")
        Exit 2;
    }
}

$orgId = ReadOrgIdFromOnboardingScript($onboardingScript);
if ([string]::IsNullOrEmpty($orgId))
{
    Write-Host -ForegroundColor Red "Could not deduct organization id from onboarding script:" $onboardingScript
    Trace("Could not deduct organization id from onboarding script")
    Exit 3;
}
Write-Host "Identified organization id:" $orgId
Trace("Identified OrgId:" + $orgId)

$computerName = GetComputerName;
Write-Host "Identified computer name:" $computerName
Trace("Identified computer name:" + $computerName)

$id = $orgId + "_" + $computerName;
$senseGuid = CreateGuidFromString($id);
Write-Host "Generated senseGuid:" $senseGuid
Trace("Generated "+ "from id:" + $id +"senseGuid:" + $senseGuid)


$senseGuidRegPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Advanced Threat Protection"
$senseGuidValueName = "senseGuid";
$populatedSenseGuid = [Microsoft.Win32.Registry]::GetValue($senseGuidRegPath, $senseGuidValueName, $null)
$senseState = (Get-Service -Name "SENSE").Status
if ($populatedSenseGuid)
{
    Write-Host -ForegroundColor Red "SenseGuid already populated:" $populatedSenseGuid
    Trace("SenseGuid already populated. Attempting to clear SenseGuid if SENSE is stopped.")
    if ($senseState -eq "Stopped") 
    {
        [Microsoft.Win32.Registry]::SetValue($senseGuidRegPath, $senseGuidValueName, "")
        Trace("Sense service is stopped. Remove SesnseGuid value.")
    } else
    { 
        Write-Host -ForegroundColor Red "SENSE service state is:" $senseState
        Trace("Sense service is not stopped. Exiting script.")
        Exit 4;
    }
} 
[Microsoft.Win32.Registry]::SetValue($senseGuidRegPath, $senseGuidValueName, $senseGuid)
Write-Host "SenseGuid was set:" $senseGuid
Trace("SenseGuid was set:" + $senseGuid)

$vdiTagRegPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Advanced Threat Protection\DeviceTagging"
$vdiTagValueName = "VDI";
$vdiTag = "NonPersistent";
[Microsoft.Win32.Registry]::SetValue($vdiTagRegPath, $vdiTagValueName, $vdiTag)
Write-Host "VDI tag was set:" $vdiTag
Trace("VDI tag was set:"+ $vdiTag)

Write-Host "Starting onboarding"
&$onboardingScript
if ($LASTEXITCODE -ne 0)
{
    Write-Host -ForegroundColor Red "Failed to onboard sense service from: $($onboardingScript). Exit code: $($LASTEXITCODE). To troubleshoot, please read https://technet.microsoft.com/en-us/itpro/windows/keep-secure/troubleshoot-onboarding-windows-defender-advanced-threat-protection"
    Trace("Failed to onboard sense service. LASTEXITCODE=" + $LASTEXITCODE)
    Exit 5;
}

Write-Host -ForegroundColor Green "Onboarding completed successfully"
Trace("SUCCESS")
# SIG # Begin signature block
# MIIoSwYJKoZIhvcNAQcCoIIoPDCCKDgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD91lv7mOkQk0RH
# JsElhN1oXrhYa7CDUeCDS9It8OOOH6CCDZcwggYVMIID/aADAgECAhMzAAADcaWg
# nFyRHuruAAAAAANxMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjMwNTExMTg0MTEzWhcNMjQwNTA4MTg0MTEzWjCBlDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjE+MDwGA1UEAxM1TWlj
# cm9zb2Z0IFdpbmRvd3MgRGVmZW5kZXIgQWR2YW5jZWQgVGhyZWF0IFByb3RlY3Rp
# b24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDQl+fOHFGkNfDHrcv3
# g8shIsUp58WmSbtNm4uu7Sw75Wgsgo5p2yYGGqiRWbu0eIKhAJ1bRp9Qa7vAjMEw
# d0wf9wlLjDNAITzDsokwoCl0rOgWxzYuGSusZq4e/liClIpY5fuxrpsEnsssR1o6
# jITkdJQ6ZkWsTFETxLLOEGxe9BkTkXZaBOHlhTt5QIq6UB6j8zNN/Vo4rFmq751X
# lQLA1jOnNi5NOS3/11TW16ZCo9XKG22zdNsJCUckT/QH2eeQNgpuyfIvP06o+RpP
# Uo7P4xdc4c74S3HKfRiNuqbs3+xvb22GtXIz3cKFDhILpNKN/SC8qLjizq0PxwL1
# lr1ZAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBggrBgEFBQcDAwYKKwYBBAGCN0wv
# ATAdBgNVHQ4EFgQUcR5wDY+Mh5A/I7scm54A8ODeSVcwRQYDVR0RBD4wPKQ6MDgx
# HjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEWMBQGA1UEBRMNNDUxODk0
# KzUwMTAwNTAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8E
# TTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9N
# aWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBR
# BggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0
# cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAw
# DQYJKoZIhvcNAQELBQADggIBAKYhzPfo4pWE2MYg2W1VnHJ7NZ/nwEpGYEz7Qhqc
# bPj2sJFFhnUzYHOAyXz4vP0+ERhFw9lrqLvoyj8s6xQU11QPQVItopahH65USGWh
# UcyrXFBVSx7MG3Dwi+NT6rxq9MjY3KLB1hZPF7hgtOjWgtjXgeJOsy3IjPiRkDwX
# 5b5Pg6o8Xpyt84mpvAPsDKO7yJGJq8V528deIYh+0DcELvUZTtl4Kz8ElT4BxF6i
# XxXkuqpCWO/rwEa6HrLNV2udND/AImVio09bbZXOWBcb9uTTNezYX5fZvinIX7hl
# UHHIDaVUqqwTFtac8q7BLE02T0P7NAeBtayujIQFzGNuwLN302UmUWAyc4LynqZa
# h2OmZWcMODUCuHIMP3pk54XjWt0YYEWPFAbA7T7j8wjby/vPXdG93LybID/yjGDb
# U1t5xMoEpN5rvSUM1U42iJ1tF268/nE2/8nKqUpdJXH/MaXxYU3FnbshmIe1xfxF
# NjeMYN4jg+5gjz5SBzHAhT1X9QWXNOhAXxib3wcchlsxFYtSNihHLEJ2GuckRuPi
# 47VWi/3hTTnl88S8r3jsbWLatGbQxcbrsF4sglAvFD9SQSXLGUsE5wz/1p/Gb1Fh
# qfNBc6E4AWVj9+A1KezSnMBAw8gJk3fiRkdxfSfpLOkHvgA7qsOmQ7qwjs05kWZf
# 055CMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWlj
# cm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4
# MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBD
# QSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3Y
# bqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUB
# FDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnbo
# MlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT
# +OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuy
# e4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEh
# NSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2
# z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3
# s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78Ic
# V9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E
# 11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5P
# M4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcV
# AQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3
# FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAf
# BgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBL
# hklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNS
# b29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggr
# BgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNS
# b29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsG
# AQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwA
# ZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0G
# CSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDB
# ZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc
# 8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYq
# wooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu
# 5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWI
# UUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXh
# j38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yH
# PgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtI
# EJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4Guzq
# N5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgR
# MiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQ
# zTGCGgowghoGAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEC
# EzMAAANxpaCcXJEe6u4AAAAAA3EwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcN
# AQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUw
# LwYJKoZIhvcNAQkEMSIEICnF+KNlmmPX2ST/0Q68SwMxk/UbrJP1q6/tRdVITz5Z
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAPVsVxRS1qCjk
# 6jcA+vqbE2d8XbUxFGP4XVAJBphkS456HgtOOJEtwMCFSGw+zEAifxsTsDXfQ79K
# YxlXU39JF0S2NvOM5HO0djYga/I+l0dz5MmXaYyZUuusKn3TnTrhjN2SF008q2+K
# 1XtaEaxKarfa1Pyyr11VbKoafNE4msSZ+rUPRZbBjSyQRPXYVFTUYdhGBWqHwZtJ
# czAL4hlECMJPEQpg59e9rk6zx3/9uUWzBJJ4clTCw1ZJq7rB6jJJp0iOh6q/ldje
# F33oQ75g9pMJRcMWTIEOZfQvohpvNXnDR4q6pszaeORPTT9T5V363yT53TOeUTfD
# HhyFs4wwiqGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCC
# F20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEE
# ggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCfhekdp4gI
# w5rPKZWJkhp7RP52cekPQr07l245tKK5qwIGZXsRPezCGBMyMDI0MDEwNzEzMjgz
# OS4yMTlaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25z
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODkwMC0wNUUwLUQ5NDcxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIB
# AgITMwAAAdMdMpoXO0AwcwABAAAB0zANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yMzA1MjUxOTEyMjRaFw0yNDAyMDExOTEy
# MjRaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046ODkwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQC0jquTN4g1xbhXCc8MV+dOu8Uqc3KbbaWti5vdsAWM1D4fVSi+4NWgGtP/BVRY
# rVj2oVnnMy0eazidQOJ4uUscBMbPHaMxaNpgbRG9FEQRFncAUptWnI+VPl53PD6M
# PL0yz8cHC2ZD3weF4w+uMDAGnL36Bkm0srONXvnM9eNvnG5djopEqiHodWSauRye
# 4uftBR2sTwGHVmxKu0GS4fO87NgbJ4VGzICRyZXw9+RvvXMG/jhM11H8AWKzKpn0
# oMGm1MSMeNvLUWb31HSZekx/NBEtXvmdo75OV030NHgIXihxYEeSgUIxfbI5OmgM
# q/VDCQp2r/fy/5NVa3KjCQoNqmmEM6orAJ2XKjYhEJzop4nWCcJ970U6rXpBPK4X
# GNKBFhhLa74TM/ysTFIrEXOJG1fUuXfcdWb0Ex0FAeTTr6gmmCqreJNejNHffG/V
# EeF7LNvUquYFRndiCUhgy624rW6ptcnQTiRfE0QL/gLF41kA2vZMYzcc16EiYXQQ
# BaF3XAtMduh1dpXqTPPQEO3Ms5/5B/KtjhSspMcPUvRvb35IWN+q+L+zEwiphmnC
# GFTuyOMqc5QE0ruGN3Mx0Vv6x/hcOmaXxrHQGpNKI5Pn79Yk89AclqU2mXHz1ZHW
# p+KBc3D6VP7L32JlwxhJx3asa085xv0XPD58MRW1WaGvaQIDAQABo4IBSTCCAUUw
# HQYDVR0OBBYEFNLHIIa4FAD494z35hvzCmm0415iMB8GA1UdIwQYMBaAFJ+nFV0A
# XmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQ
# Q0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYD
# VR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEB
# CwUAA4ICAQBAYlhYoUQ+4aaQ54MFNfE6Ey8v4rWv+LtDRSjMM2X9g4uanA9cU7Vi
# tdpIPV/zE6v4AEhe/Vng2UAR5qj2SV3sz+fDqN6VLWUZsKR0QR2JYXKnFPRVj16e
# zZyP7zd5H8IsvscEconeX+aRHF0xGGM4tDLrS84vj6Rm0bgoWLXWnMTZ5kP4ownG
# mm0LsmInuu0GKrDZnkeTVmfk8gTTy8d1y3P2IYc2UI4iJYXCuSaKCuFeO0wqyscp
# vhGQSno1XAFK3oaybuD1mSoQxT9q77+LAGGQbiSoGlgTjQQayYsQaPcG1Q4QNwON
# GqkASCZTbzJlnmkHgkWlKSLTulOailWIY4hS1EZ+w+sX0BJ9LcM142h51OlXLMoP
# LpzHAb6x22ipaAJ5Kf3uyFaOKWw4hnu0zWs+PKPd192ndeK2ogWfaFdfnEvkWDDH
# 2doL+ZA5QBd8Xngs/md3Brnll2BkZ/giZE/fKyolriR3aTAWCxFCXKIl/Clu2bbn
# j9qfVYLpAVQEcPaCfTAf7OZBlXmluETvq1Y/SNhxC6MJ1QLCnkXSI//iXYpmRKT7
# 83QKRgmo/4ztj3uL9Z7xbbGxISg+P0HTRX15y4TReBbO2RFNyCj88gOORk+swT1k
# aKXUfGB4zjg5XulxSby3uLNxQebE6TE3cAK0+fnY5UpHaEdlw4e7ijCCB3EwggVZ
# oAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jv
# c29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4
# MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvX
# JHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa
# /rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AK
# OG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rbo
# YiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIck
# w+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbni
# jYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F
# 37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZ
# fD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIz
# GHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR
# /bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1
# Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUC
# AwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0O
# BBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yD
# fQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkr
# BgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUw
# AwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBN
# MEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0
# cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoG
# CCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01p
# Y1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9
# /Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5
# bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvf
# am++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn
# 0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlS
# dYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0
# j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5
# JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakUR
# R6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4
# O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVn
# K+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoI
# Yn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNNMIICNQIBATCB+aGB0aSB
# zjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UE
# CxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVs
# ZCBUU1MgRVNOOjg5MDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQBSx23cMcNB1IQws/LYkRXa
# 7I5JsKCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBCwUAAgUA6USKMDAiGA8yMDI0MDEwNzAyMjU1MloYDzIwMjQwMTA4MDIy
# NTUyWjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDpRIowAgEAMAcCAQACAgLWMAcC
# AQACAhRDMAoCBQDpRduwAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
# AwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAIPu
# NhLArpWUxl2AJ8dF5imb4IYtRTA1pnhwyWlPG159VjhkDWF5Y9aQsUYBZ0Gz8RUD
# TsKgvy5mtoCpyKKMKlxmVnff823mT7p4sm9v3To96F6x0BF4VFqILIWYkJ4XY52y
# 0VzjstJS/VColvNP6E0oUZxkgjGoUvvh/itVQlLcUWWGS2aFC99aXldMJnUwDPZ1
# AMn+a7UEV+Lah3xElV2ViSEQWGHKO1ecwffrRWLar9YreVzwGKjyB9vwpYCM/fvG
# MD7l7mySQzdrz/leEViXEDSUpX57vB8s9U8KdRzIiZjattD/yDeJLd4/gh+i2vGQ
# UGIgoKHm8fP41ylOfUoxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMAITMwAAAdMdMpoXO0AwcwABAAAB0zANBglghkgBZQMEAgEFAKCC
# AUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCAS
# qR2nNl2Jus2MXlDA1JY3Kqif/NG9MqZklFXLBKdrzTCB+gYLKoZIhvcNAQkQAi8x
# geowgecwgeQwgb0EIJJm9OrE4O5PWA1KaFaztr9uP96rQgEn+tgGtY3xOqr1MIGY
# MIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAHTHTKaFztA
# MHMAAQAAAdMwIgQg4hTYev5CEQK5r73eUiJw4f57mZQ7raPDCpC6GB1m0TYwDQYJ
# KoZIhvcNAQELBQAEggIALm2UDa360zWcZGGHcyhaTStXNzSHe98ZAK4V0Eo3hSQm
# RiWxTi8WsmHhQ7StIxSg5MeVrcwxDeNOi+7CHi0OrSFr6MauOry87lhDW2BgxbHf
# AGPaXauVH26j2kIsyaDqXYKaOslOkT89Hl6AtCHCDtRg/GUckCuASNF4n3EcGFcq
# zOOnDM7TNzp/y5eYApCyigh213rtzJ0cOJFarA0Hg5sOhIrvAWzgrA9RwXIKj/wn
# v1+oFUwjMgYIz9ZYFQoRQA0gOFFPDOamColoXN2bMD49tu4HznijyHiEoLHc0RAo
# fKNNJK0BnyW0RZ944JIleBR7B6+TnipBTwzE8N8kc7c7gaa1/nHhSpDBy53QDEoF
# 0aK395SZgSSqZ6UzOPJfr6omcgDFBeyQoKXcQlj3hTO6Q5Y9cm2jN2H2HP0tY90c
# VhYctpexRl1WqlrzYj3uEXEaMH2FyGegRAQkyp5kfBVkKfhnu9eGmhnf22mMUhNy
# Pb1snAUX8w33q1Ay4ocf+dnawo5sPg/D0/o21Y4LtFGldx8ommfdAO8o+9Y2U9yr
# Qpkkq+eCDhzRCRmYrMmk4+x3F5yt3YBpOh7ubn+rkCYmga/yzCwDDc5c5m221BIP
# hk/WmVLEJCbD4/S7ResOQL7GR4bBSSqZIdNqqbVBiSUbWGncfZJ9Kz+OT6nDfA8=
# SIG # End signature block
