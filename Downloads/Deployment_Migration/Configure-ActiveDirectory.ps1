# =============================================================================
# ACTIVE DIRECTORY CONFIGURATION SCRIPT
# Domain join, OU placement, and security group management
# =============================================================================
# Usage: .\Configure-ActiveDirectory.ps1 -Territory "US" -ServerName "USSUPDEP01"
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("US", "EU", "APAC", "CA", "AU")]
    [string]$Territory,
    
    [Parameter(Mandatory=$true)]
    [string]$ServerName,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Production", "Staging", "Development")]
    [string]$Environment = "Production",
    
    [Parameter(Mandatory=$false)]
    [PSCredential]$DomainCredential,
    
    [Parameter(Mandatory=$false)]
    [switch]$RemoveOldServer,
    
    [Parameter(Mandatory=$false)]
    [switch]$Restart
)

# Require Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    exit 1
}

# Check if running from domain-joined machine
try {
    $Domain = Get-ADDomain -ErrorAction Stop
    $IsOnDomain = $true
} catch {
    $IsOnDomain = $false
}

# Territory Configuration
$TerritoryConfig = @{
    "US" = @{
        Domain = "company.local"
        OU_Path = "OU=Deployment Servers,OU=Servers,OU=Resources,DC=company,DC=local"
        RootDC = "DC=company,DC=local"
        SecurityGroups = @("ROLE-GPO_CENTRAL-SERVER", "ROLE-SERVER-ADMINS")
    }
    "EU" = @{
        Domain = "eu.company.local"
        OU_Path = "OU=Deployment Servers,OU=Servers,OU=Resources,DC=eu,DC=company,DC=local"
        RootDC = "DC=eu,DC=company,DC=local"
        SecurityGroups = @("ROLE-GPO_CENTRAL-SERVER", "ROLE-SERVER-ADMINS")
    }
    "APAC" = @{
        Domain = "apac.company.local"
        OU_Path = "OU=Deployment Servers,OU=Servers,OU=Resources,DC=apac,DC=company,DC=local"
        RootDC = "DC=apac,DC=company,DC=local"
        SecurityGroups = @("ROLE-GPO_CENTRAL-SERVER", "ROLE-SERVER-ADMINS")
    }
    "CA" = @{
        Domain = "ca.company.local"
        OU_Path = "OU=Deployment Servers,OU=Servers,OU=Resources,DC=ca,DC=company,DC=local"
        RootDC = "DC=ca,DC=company,DC=local"
        SecurityGroups = @("ROLE-GPO_CENTRAL-SERVER", "ROLE-SERVER-ADMINS")
    }
    "AU" = @{
        Domain = "au.company.local"
        OU_Path = "OU=Deployment Servers,OU=Servers,OU=Resources,DC=au,DC=company,DC=local"
        RootDC = "DC=au,DC=company,DC=local"
        SecurityGroups = @("ROLE-GPO_CENTRAL-SERVER", "ROLE-SERVER-ADMINS")
    }
}

if (-not $TerritoryConfig.ContainsKey($Territory)) {
    Write-Host "ERROR: Invalid territory '$Territory'" -ForegroundColor Red
    Write-Host "Valid options: $(($TerritoryConfig.Keys) -join ', ')" -ForegroundColor Red
    exit 1
}

$Config = $TerritoryConfig[$Territory]
$TranscriptPath = "C:\Logs\ADConfiguration_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Create logs directory
if (-not (Test-Path "C:\Logs")) {
    New-Item -ItemType Directory -Path "C:\Logs" -Force | Out-Null
}

Start-Transcript -Path $TranscriptPath

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              ACTIVE DIRECTORY CONFIGURATION SCRIPT                            ║" -ForegroundColor Cyan
Write-Host "║   Territory: $Territory | Server: $ServerName | Environment: $Environment     ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = "Continue"

# =============================================================================
# 1. RENAME COMPUTER (if needed)
# =============================================================================

Write-Host "Step 1: Verifying Computer Name..." -ForegroundColor Yellow

$CurrentName = $env:COMPUTERNAME

if ($CurrentName -ne $ServerName) {
    Write-Host "Current name: $CurrentName"
    Write-Host "Target name: $ServerName"
    Write-Host ""
    Write-Host "Computer will be renamed on next step (requires reboot)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To rename computer, run:"
    Write-Host "  Rename-Computer -NewName '$ServerName' -Restart"
    Write-Host ""
    Write-Host "Press ENTER to continue after renaming the computer..."
    Read-Host
} else {
    Write-Host "✓ Computer name is correct: $ServerName" -ForegroundColor Green
}

# =============================================================================
# 2. JOIN DOMAIN
# =============================================================================

Write-Host ""
Write-Host "Step 2: Joining Domain..." -ForegroundColor Yellow

try {
    # Check if already on domain
    $PartOf = Get-ADComputer -Filter "Name -eq '$ServerName'" -ErrorAction SilentlyContinue
    
    if ($PartOf) {
        Write-Host "✓ Computer $ServerName is already in domain $($Config.Domain)" -ForegroundColor Green
    } else {
        Write-Host "Computer is not in domain. Domain join required."
        Write-Host "Domain: $($Config.Domain)"
        
        if ($null -eq $DomainCredential) {
            $DomainCredential = Get-Credential -Message "Enter domain admin credentials for $($Config.Domain)"
        }
        
        Write-Host "Attempting to join domain..."
        Add-Computer -DomainName $Config.Domain -Credential $DomainCredential -OUPath $Config.OU_Path -Force -ErrorAction Stop
        
        Write-Host "✓ Computer joined to domain (reboot required)" -ForegroundColor Green
        Write-Host ""
        Write-Host "System will reboot in 30 seconds. Press Ctrl+C to cancel..."
        Start-Sleep -Seconds 5
        
        Restart-Computer -Force
        exit
    }
} catch {
    Write-Host "ERROR: Failed to join domain: $_" -ForegroundColor Red
    Write-Host "Please verify credentials and network connectivity"
    Write-Host ""
    Write-Host "Manual domain join command:"
    Write-Host "  Add-Computer -DomainName '$($Config.Domain)' -Credential (Get-Credential) -OUPath '$($Config.OU_Path)' -Force -Restart"
}

# =============================================================================
# 3. VERIFY DOMAIN MEMBERSHIP
# =============================================================================

Write-Host ""
Write-Host "Step 3: Verifying Domain Membership..." -ForegroundColor Yellow

try {
    $Computer = Get-ADComputer -Identity $ServerName -Server $Config.Domain -ErrorAction Stop
    Write-Host "✓ Computer found in Active Directory" -ForegroundColor Green
    Write-Host "  Name: $($Computer.Name)"
    Write-Host "  DN: $($Computer.DistinguishedName)"
    Write-Host "  Enabled: $($Computer.Enabled)"
} catch {
    Write-Host "ERROR: Computer not found in Active Directory: $_" -ForegroundColor Red
    Write-Host "The computer may need time to propagate in AD. Retry in a few moments."
}

# =============================================================================
# 4. MOVE TO CORRECT OU
# =============================================================================

Write-Host ""
Write-Host "Step 4: Moving Server to Correct OU..." -ForegroundColor Yellow

try {
    $Computer = Get-ADComputer -Identity $ServerName -Server $Config.Domain -ErrorAction Stop
    $CurrentOU = $Computer.DistinguishedName.Split(",", 2)[1]
    $TargetOU = $Config.OU_Path
    
    if ($CurrentOU -ne $TargetOU) {
        Write-Host "Current OU: $CurrentOU"
        Write-Host "Target OU: $TargetOU"
        
        Move-ADObject -Identity $Computer.ObjectGUID -TargetPath $TargetOU -Server $Config.Domain -ErrorAction Stop
        Write-Host "✓ Server moved to correct OU" -ForegroundColor Green
    } else {
        Write-Host "✓ Server is already in correct OU" -ForegroundColor Green
    }
} catch {
    Write-Host "ERROR: Failed to move server to OU: $_" -ForegroundColor Red
}

# =============================================================================
# 5. ADD TO SECURITY GROUPS
# =============================================================================

Write-Host ""
Write-Host "Step 5: Adding Server to Security Groups..." -ForegroundColor Yellow

try {
    $Computer = Get-ADComputer -Identity $ServerName -Server $Config.Domain -ErrorAction Stop
    
    foreach ($GroupName in $Config.SecurityGroups) {
        try {
            $Group = Get-ADGroup -Identity $GroupName -Server $Config.Domain -ErrorAction SilentlyContinue
            
            if ($Group) {
                # Check if already a member
                $Member = Get-ADGroupMember -Identity $GroupName -Server $Config.Domain | 
                    Where-Object { $_.SamAccountName -eq $Computer.SamAccountName }
                
                if ($Member) {
                    Write-Host "✓ Already member of: $GroupName" -ForegroundColor Green
                } else {
                    Add-ADGroupMember -Identity $GroupName -Members $Computer -Server $Config.Domain -ErrorAction Stop
                    Write-Host "✓ Added to security group: $GroupName" -ForegroundColor Green
                }
            } else {
                Write-Host "! Security group not found: $GroupName" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "ERROR: Failed to add to group $GroupName`: $_" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "ERROR: Could not process security groups: $_" -ForegroundColor Red
}

# =============================================================================
# 6. ADD ENVIRONMENT-SPECIFIC ATTRIBUTES
# =============================================================================

Write-Host ""
Write-Host "Step 6: Setting Computer Attributes..." -ForegroundColor Yellow

try {
    $Computer = Get-ADComputer -Identity $ServerName -Server $Config.Domain
    
    Set-ADComputer -Identity $Computer -Description "Deployment Server - Territory: $Territory - Environment: $Environment" `
        -Server $Config.Domain -ErrorAction Stop
    
    Write-Host "✓ Computer attributes updated" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to update computer attributes: $_" -ForegroundColor Red
}

# =============================================================================
# 7. REMOVE OLD SERVER (if requested)
# =============================================================================

if ($RemoveOldServer) {
    Write-Host ""
    Write-Host "Step 7: Removing Old Server from Domain..." -ForegroundColor Yellow
    
    $OldServerName = $Territory + "SUPDEP01-OLD"
    
    try {
        $OldComputer = Get-ADComputer -Identity $OldServerName -Server $Config.Domain -ErrorAction SilentlyContinue
        
        if ($OldComputer) {
            Write-Host "Found old server: $OldServerName"
            Write-Host "This computer object will be deleted from Active Directory"
            Write-Host ""
            
            $Confirmation = Read-Host "Confirm deletion of $OldServerName ? (yes/no)"
            
            if ($Confirmation -eq "yes") {
                Remove-ADComputer -Identity $OldComputer -Confirm:$false -Server $Config.Domain
                Write-Host "✓ Old server removed from Active Directory" -ForegroundColor Green
            } else {
                Write-Host "Deletion cancelled" -ForegroundColor Yellow
            }
        } else {
            Write-Host "! Old server $OldServerName not found in Active Directory" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "ERROR: Failed to remove old server: $_" -ForegroundColor Red
    }
}

# =============================================================================
# 8. UPDATE GROUP POLICY
# =============================================================================

Write-Host ""
Write-Host "Step 8: Updating Group Policy..." -ForegroundColor Yellow

try {
    Write-Host "Forcing group policy update..."
    gpupdate /force /sync
    Write-Host "✓ Group policy updated" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to update group policy: $_" -ForegroundColor Red
}

# =============================================================================
# 9. VERIFY CONFIGURATION
# =============================================================================

Write-Host ""
Write-Host "Step 9: Verifying Configuration..." -ForegroundColor Yellow

try {
    $Computer = Get-ADComputer -Identity $ServerName -Server $Config.Domain -Properties * -ErrorAction Stop
    
    Write-Host ""
    Write-Host "Computer Details:" -ForegroundColor White
    Write-Host "  Name: $($Computer.Name)"
    Write-Host "  Enabled: $($Computer.Enabled)"
    Write-Host "  OU: $($Computer.DistinguishedName.Split(",", 2)[1])"
    Write-Host "  Modified: $($Computer.Modified)"
    Write-Host "  Description: $($Computer.Description)"
    
    Write-Host ""
    Write-Host "Security Group Membership:" -ForegroundColor White
    $Groups = Get-ADPrincipalGroupMembership -Identity $ServerName -Server $Config.Domain | 
        Where-Object { $_.Name -ne "Domain Computers" }
    
    foreach ($Group in $Groups) {
        Write-Host "  ✓ $($Group.Name)" -ForegroundColor Green
    }
    
} catch {
    Write-Host "ERROR: Failed to verify configuration: $_" -ForegroundColor Red
}

# =============================================================================
# 10. SUMMARY & NEXT STEPS
# =============================================================================

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                     CONFIGURATION COMPLETE                                    ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  Territory: $Territory"
Write-Host "  Domain: $($Config.Domain)"
Write-Host "  Server: $ServerName"
Write-Host "  OU: $($Config.OU_Path)"
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Verify DNS settings are correct for server name resolution"
Write-Host "2. Test domain authentication (whoami should show domain\username)"
Write-Host "3. Verify security group memberships on the server"
Write-Host "4. Check Group Policy application"
Write-Host "5. Proceed with DFS replication configuration"
Write-Host ""

Write-Host "Transcript saved to: $TranscriptPath"
Write-Host ""

# Check domain authentication
Write-Host "Current User Context:" -ForegroundColor White
whoami /upn

if ($Restart) {
    Write-Host ""
    Write-Host "System will restart in 30 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    Restart-Computer -Force
}

Stop-Transcript
