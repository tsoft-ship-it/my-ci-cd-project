###Tasks Covered##
==============================================================================
#Disable IPv6 on Ethernet
#Set primary and secondary DNS to the territory's Central DCs
#Update the timezone
#Disable the firewall
#Perform Windows Updates
#Disable Windows Updates Service
==============================================================================
# ==============================================================================
# CONFIGURATION PARAMETERS 
# ==============================================================================
$AdapterName   = "Ethernet"
$PrimaryDNS    = "XX.XX.X.X"       # Primary Central DC IP
$SecondaryDNS  = "XX.XX.X.X"       # Secondary Central DC IP
$TimeZone      = "territory Standard Time" # Use 'Get-TimeZone -ListAvailable' for exact names

# ==============================================================================
# SCRIPT EXECUTION
# ==============================================================================

Write-Host "Starting System Configuration..." -ForegroundColor Cyan

# 1. Disable IPv6 on the specified interface
Write-Host "Disabling IPv6 on adapter '$AdapterName'..." -ForegroundColor Yellow
Disable-NetAdapterBinding -Name $AdapterName -ComponentID ms_tcpip6 -ErrorAction Stop

# 2. Change Primary and Secondary DNS Servers
Write-Host "Updating IPv4 DNS Server addresses..." -ForegroundColor Yellow
Set-DnsClientServerAddress -InterfaceAlias $AdapterName -ServerAddresses ($PrimaryDNS, $SecondaryDNS)

# 3. Update System Timezone
Write-Host "Updating system timezone to '$TimeZone'..." -ForegroundColor Yellow
Set-TimeZone -Id $TimeZone

# 4. Disable Windows Firewall across Domain, Private, and Public profiles
Write-Host "Disabling Windows Firewall across all profiles..." -ForegroundColor Yellow
Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled False

Write-Host "`nConfiguration Complete!" -ForegroundColor Green

# 5. Perform Windows Updates (must run BEFORE the update service is disabled)
Write-Host "Installing Windows Updates (this may take a while)..." -ForegroundColor Yellow
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
}
if (-not (Get-Module -ListAvailable -Name $UpdateModule)) {
    Install-Module -Name $UpdateModule -Force -Scope AllUsers
}
Import-Module $UpdateModule
Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot
$RebootNeeded = Get-WURebootStatus -Silent

# 6. Disable Windows Update service(s)
Write-Host "Disabling Windows Update services: $($UpdateServices -join ', ')..." -ForegroundColor Yellow
foreach ($Service in $UpdateServices) {
    Stop-Service -Name $Service -Force -ErrorAction SilentlyContinue
    Set-Service  -Name $Service -StartupType Disabled
}

Write-Host "`nConfiguration Complete!" -ForegroundColor Green
if ($RebootNeeded) {
    Write-Host "A reboot is required to finish installing updates." -ForegroundColor Red
}