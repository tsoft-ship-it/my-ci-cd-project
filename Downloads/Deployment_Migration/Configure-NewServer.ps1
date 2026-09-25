# =============================================================================
# NEW SERVER CONFIGURATION SCRIPT
# Run on newly launched XXSUPDEP01 instance
# =============================================================================
# Usage: .\Configure-NewServer.ps1 -Territory "US"
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("US", "EU", "APAC", "CA", "AU")]
    [string]$Territory,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipUpdates,
    
    [Parameter(Mandatory=$false)]
    [switch]$Restart
)

# Require Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = "Stop"

# Territory Configuration
$TerritoryConfig = @{
    "US" = @{
        Primary_DNS = "10.1.1.10"
        Secondary_DNS = "10.1.1.20"
        TimeZone = "Central Standard Time"
        Domain = "company.local"
        DNSSUFFIX = "company.local"
    }
    "EU" = @{
        Primary_DNS = "10.2.1.10"
        Secondary_DNS = "10.2.1.20"
        TimeZone = "Romance Standard Time"
        Domain = "eu.company.local"
        DNSSUFFIX = "eu.company.local"
    }
    "APAC" = @{
        Primary_DNS = "10.3.1.10"
        Secondary_DNS = "10.3.1.20"
        TimeZone = "Singapore Standard Time"
        Domain = "apac.company.local"
        DNSSUFFIX = "apac.company.local"
    }
    "CA" = @{
        Primary_DNS = "10.4.1.10"
        Secondary_DNS = "10.4.1.20"
        TimeZone = "Eastern Standard Time"
        Domain = "ca.company.local"
        DNSSUFFIX = "ca.company.local"
    }
    "AU" = @{
        Primary_DNS = "10.5.1.10"
        Secondary_DNS = "10.5.1.20"
        TimeZone = "AUS Eastern Standard Time"
        Domain = "au.company.local"
        DNSSUFFIX = "au.company.local"
    }
}

if (-not $TerritoryConfig.ContainsKey($Territory)) {
    Write-Host "ERROR: Invalid territory '$Territory'" -ForegroundColor Red
    Write-Host "Valid options: $(($TerritoryConfig.Keys) -join ', ')" -ForegroundColor Red
    exit 1
}

$Config = $TerritoryConfig[$Territory]
$TranscriptPath = "C:\Logs\Configuration_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Create logs directory
if (-not (Test-Path "C:\Logs")) {
    New-Item -ItemType Directory -Path "C:\Logs" -Force | Out-Null
}

Start-Transcript -Path $TranscriptPath

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    NEW SERVER CONFIGURATION SCRIPT                             ║" -ForegroundColor Cyan
Write-Host "║                        Territory: $Territory                                     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# 1. DISABLE IPv6
# =============================================================================

Write-Host "Step 1: Disabling IPv6..." -ForegroundColor Yellow

try {
    $Adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($Adapter) {
        Write-Host "Found adapter: $($Adapter.Name) ($($Adapter.InterfaceDescription))"
        
        Disable-NetAdapterBinding -Name $Adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
        Write-Host "✓ IPv6 disabled for $($Adapter.Name)" -ForegroundColor Green
    } else {
        Write-Host "! No active network adapter found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Failed to disable IPv6: $_" -ForegroundColor Red
}

# =============================================================================
# 2. CONFIGURE DNS
# =============================================================================

Write-Host ""
Write-Host "Step 2: Configuring DNS..." -ForegroundColor Yellow

try {
    $Adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    
    if ($Adapter) {
        Write-Host "Setting DNS servers:"
        Write-Host "  Primary: $($Config.Primary_DNS)"
        Write-Host "  Secondary: $($Config.Secondary_DNS)"
        
        Set-DnsClientServerAddress -InterfaceAlias $Adapter.Name `
            -ServerAddresses @($Config.Primary_DNS, $Config.Secondary_DNS)
        
        Write-Host "Setting DNS suffix: $($Config.DNSSUFFIX)"
        Set-DnsClient -InterfaceAlias $Adapter.Name `
            -ConnectionSpecificSuffix $Config.DNSSUFFIX `
            -RegisterThisConnectionsAddress $true `
            -UseSuffixWhenRegistering $true
        
        Write-Host "✓ DNS configured successfully" -ForegroundColor Green
        
        # Verify DNS settings
        Write-Host ""
        Write-Host "Verifying DNS configuration..." -ForegroundColor White
        Get-DnsClientServerAddress -InterfaceAlias $Adapter.Name -AddressFamily IPv4 | Format-Table
    } else {
        Write-Host "ERROR: No active network adapter found" -ForegroundColor Red
    }
} catch {
    Write-Host "ERROR: Failed to configure DNS: $_" -ForegroundColor Red
}

# =============================================================================
# 3. CONFIGURE TIMEZONE
# =============================================================================

Write-Host ""
Write-Host "Step 3: Configuring Timezone..." -ForegroundColor Yellow

try {
    Write-Host "Setting timezone to: $($Config.TimeZone)"
    
    Set-TimeZone -Name $Config.TimeZone
    
    $CurrentTZ = Get-TimeZone
    Write-Host "✓ Timezone configured: $($CurrentTZ.DisplayName)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to configure timezone: $_" -ForegroundColor Red
}

# =============================================================================
# 4. DISABLE WINDOWS FIREWALL
# =============================================================================

Write-Host ""
Write-Host "Step 4: Disabling Windows Firewall..." -ForegroundColor Yellow

try {
    Get-NetFirewallProfile | Set-NetFirewallProfile -Enabled $false
    
    Write-Host "✓ Windows Firewall disabled" -ForegroundColor Green
    
    Get-NetFirewallProfile | Format-Table Name, Enabled
} catch {
    Write-Host "ERROR: Failed to disable firewall: $_" -ForegroundColor Red
}

# =============================================================================
# 5. WINDOWS UPDATES
# =============================================================================

if (-not $SkipUpdates) {
    Write-Host ""
    Write-Host "Step 5: Checking for Windows Updates..." -ForegroundColor Yellow
    
    try {
        # Install PSWindowsUpdate module if not present
        if (-not (Get-Module PSWindowsUpdate -ListAvailable)) {
            Write-Host "Installing PSWindowsUpdate module..."
            Install-Module PSWindowsUpdate -Force -SkipPublisherCheck
        }
        
        Write-Host "Scanning for updates..."
        $Updates = Get-WindowsUpdate
        
        if ($Updates.Count -gt 0) {
            Write-Host "Found $($Updates.Count) updates available"
            Write-Host "Installing updates..."
            
            Install-WindowsUpdate -AcceptAll -AutoReboot
            Write-Host "Updates installed and system will reboot" -ForegroundColor Green
        } else {
            Write-Host "✓ System is up to date" -ForegroundColor Green
        }
    } catch {
        Write-Host "ERROR: Failed to check/install updates: $_" -ForegroundColor Red
        Write-Host "You can run Windows Update manually from Settings > Update & Security" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "Step 5: Skipping Windows Updates (--SkipUpdates flag set)" -ForegroundColor Yellow
}

# =============================================================================
# 6. DISABLE WINDOWS UPDATE SERVICE
# =============================================================================

Write-Host ""
Write-Host "Step 6: Disabling Windows Update Service..." -ForegroundColor Yellow

try {
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Set-Service -Name wuauserv -StartupType Disabled
    
    $Service = Get-Service -Name wuauserv
    Write-Host "✓ Windows Update service disabled" -ForegroundColor Green
    Write-Host "  Status: $($Service.Status)"
    Write-Host "  Startup Type: $($Service.StartupType)"
} catch {
    Write-Host "ERROR: Failed to disable Windows Update service: $_" -ForegroundColor Red
}

# =============================================================================
# 7. VERIFY CONFIGURATION
# =============================================================================

Write-Host ""
Write-Host "Step 7: Verifying Configuration..." -ForegroundColor Yellow
Write-Host ""

# Check IPv6
Write-Host "IPv6 Status:" -ForegroundColor White
$Adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if ($Adapter) {
    $IPv6Binding = Get-NetAdapterBinding -Name $Adapter.Name -ComponentID ms_tcpip6
    Write-Host "  Adapter: $($Adapter.Name)"
    Write-Host "  IPv6 Enabled: $($IPv6Binding.Enabled)"
}

# Check DNS
Write-Host ""
Write-Host "DNS Configuration:" -ForegroundColor White
Get-DnsClientServerAddress -AddressFamily IPv4 | Format-List

# Check Timezone
Write-Host ""
Write-Host "Timezone Configuration:" -ForegroundColor White
Get-TimeZone | Format-List DisplayName, StandardName

# Check Firewall
Write-Host ""
Write-Host "Firewall Configuration:" -ForegroundColor White
Get-NetFirewallProfile | Format-Table Name, Enabled

# Check Services
Write-Host ""
Write-Host "Service Status:" -ForegroundColor White
Get-Service wuauserv | Format-Table Name, Status, StartType

# Network Connectivity
Write-Host ""
Write-Host "Network Connectivity Test:" -ForegroundColor White

$DNSServers = @($Config.Primary_DNS, $Config.Secondary_DNS)
foreach ($DNS in $DNSServers) {
    try {
        $Result = Test-Connection -ComputerName $DNS -Count 1 -ErrorAction SilentlyContinue
        if ($Result) {
            Write-Host "  ✓ DNS Server $DNS - Reachable" -ForegroundColor Green
        } else {
            Write-Host "  ✗ DNS Server $DNS - Unreachable" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ✗ DNS Server $DNS - Error: $_" -ForegroundColor Red
    }
}

# =============================================================================
# 8. SUMMARY
# =============================================================================

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                      CONFIGURATION COMPLETE                                    ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Rename the computer to match your territory (e.g., USSUPDEP01)"
Write-Host "   Example: Rename-Computer -NewName 'USSUPDEP01' -Restart"
Write-Host ""
Write-Host "2. Join the domain: $($Config.Domain)"
Write-Host "   Example: Add-Computer -DomainName '$($Config.Domain)' -Credential (Get-Credential) -Restart"
Write-Host ""
Write-Host "3. Move server to the correct OU in Active Directory"
Write-Host ""
Write-Host "4. Add server to required security groups"
Write-Host ""
Write-Host "Transcript saved to: $TranscriptPath"
Write-Host ""

if ($Restart) {
    Write-Host "System will restart in 30 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    Restart-Computer -Force
}

Stop-Transcript
