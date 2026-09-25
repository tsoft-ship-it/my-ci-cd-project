# =============================================================================
# SERVER MIGRATION AUTOMATION - COMPLETE SCRIPT
# Territory-based XXSUPDFS01 to XXSUPDEP01 Migration
# =============================================================================
# Usage: .\Migrate-Server-Complete.ps1 -Territory "US" -Phase "Pre" -Environment "Production"
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("US", "EU", "APAC", "CA", "AU")]
    [string]$Territory,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Pre", "During", "Post", "All")]
    [string]$Phase = "All",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Production", "Staging", "Development")]
    [string]$Environment = "Production",
    
    [Parameter(Mandatory=$false)]
    [string]$AMI_ID,
    
    [Parameter(Mandatory=$false)]
    [string]$InstanceType = "m5.xlarge",
    
    [Parameter(Mandatory=$false)]
    [string]$SubnetId,
    
    [Parameter(Mandatory=$false)]
    [string]$PrivateIP = "10.XXX.X.40",
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)

# =============================================================================
# CONFIGURATION
# =============================================================================

$ScriptVersion = "1.0.0"
$ScriptPath = $PSScriptRoot
$LogPath = Join-Path -Path $ScriptPath -ChildPath "Logs"
$LogFile = Join-Path -Path $LogPath -ChildPath "Migration_$Territory`_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Create log directory
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

# Territory Configuration
$TerritoryConfig = @{
    "US" = @{
        Primary_DNS = "10.1.1.10"
        Secondary_DNS = "10.1.1.20"
        TimeZone = "Central Standard Time"
        Domain = "company.local"
        DC1 = "10.1.1.10"
        DC2 = "10.1.1.20"
        OU_Path = "OU=Deployment Servers,OU=Servers,OU=Resources,DC=company,DC=local"
        Region = "us-east-1"
        VPC_CIDR = "10.1.0.0/16"
    }
    "EU" = @{
        Primary_DNS = "10.2.1.10"
        Secondary_DNS = "10.2.1.20"
        TimeZone = "Romance Standard Time"
        Domain = "eu.company.local"
        DC1 = "10.2.1.10"
        DC2 = "10.2.1.20"
        OU_Path = "OU=Deployment Servers,OU=Servers,OU=Resources,DC=eu,DC=company,DC=local"
        Region = "eu-west-1"
        VPC_CIDR = "10.2.0.0/16"
    }
    "APAC" = @{
        Primary_DNS = "10.3.1.10"
        Secondary_DNS = "10.3.1.20"
        TimeZone = "Singapore Standard Time"
        Domain = "apac.company.local"
        DC1 = "10.3.1.10"
        DC2 = "10.3.1.20"
        OU_Path = "OU=Deployment Servers,OU=Servers,OU=Resources,DC=apac,DC=company,DC=local"
        Region = "ap-southeast-1"
        VPC_CIDR = "10.3.0.0/16"
    }
    "CA" = @{
        Primary_DNS = "10.4.1.10"
        Secondary_DNS = "10.4.1.20"
        TimeZone = "Eastern Standard Time"
        Domain = "ca.company.local"
        DC1 = "10.4.1.10"
        DC2 = "10.4.1.20"
        OU_Path = "OU=Deployment Servers,OU=Servers,OU=Resources,DC=ca,DC=company,DC=local"
        Region = "ca-central-1"
        VPC_CIDR = "10.4.0.0/16"
    }
    "AU" = @{
        Primary_DNS = "10.5.1.10"
        Secondary_DNS = "10.5.1.20"
        TimeZone = "AUS Eastern Standard Time"
        Domain = "au.company.local"
        DC1 = "10.5.1.10"
        DC2 = "10.5.1.20"
        OU_Path = "OU=Deployment Servers,OU=Servers,OU=Resources,DC=au,DC=company,DC=local"
        Region = "ap-southeast-2"
        VPC_CIDR = "10.5.0.0/16"
    }
}

$Config = $TerritoryConfig[$Territory]
$ServerName = "$Territory`SUPDEP01"
$ServerNameWithYear = "$Territory`SUPDFS01-2025"
$OldServerName = "$Territory`SUPDEP01-OLD"
$DomainName = $Config.Domain

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info",
        
        [Parameter(Mandatory=$false)]
        [switch]$ConsoleOnly
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    
    # Color output to console
    switch ($Level) {
        "Info" { Write-Host $LogMessage -ForegroundColor White }
        "Warning" { Write-Host $LogMessage -ForegroundColor Yellow }
        "Error" { Write-Host $LogMessage -ForegroundColor Red }
        "Success" { Write-Host $LogMessage -ForegroundColor Green }
    }
    
    # Write to log file
    if (-not $ConsoleOnly) {
        Add-Content -Path $LogFile -Value $LogMessage
    }
}

function Write-Section {
    param([string]$Title)
    
    $Line = "=" * 80
    Write-Log -Message $Line
    Write-Log -Message ">>> $Title <<<" -Level "Info"
    Write-Log -Message $Line
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

function Test-Prerequisites {
    Write-Section "Testing Prerequisites"
    
    $MissingTools = @()
    
    # Check for required tools
    $RequiredTools = @("aws", "docker")
    
    foreach ($Tool in $RequiredTools) {
        if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
            Write-Log -Message "WARNING: $Tool not found in PATH" -Level "Warning"
        }
    }
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Log -Message "PowerShell 7+ recommended (current: $($PSVersionTable.PSVersion))" -Level "Warning"
    }
    
    # Check AWS credentials
    try {
        $Identity = aws sts get-caller-identity | ConvertFrom-Json
        Write-Log -Message "AWS Account: $($Identity.Account) - User: $($Identity.Arn)" -Level "Success"
    } catch {
        Write-Log -Message "ERROR: AWS credentials not configured. Run 'aws configure'" -Level "Error"
        return $false
    }
    
    return $true
}

function Test-NetworkConnectivity {
    param([string]$Server, [int]$Port = 3389)
    
    Write-Log -Message "Testing connection to $Server`:$Port..." -Level "Info"
    
    try {
        $TcpClient = New-Object System.Net.Sockets.TcpClient
        $AsyncResult = $TcpClient.BeginConnect($Server, $Port, $null, $null)
        $wait = $AsyncResult.AsyncWaitHandle.WaitOne(2000, $false)
        
        if ($wait) {
            $TcpClient.EndConnect($AsyncResult)
            Write-Log -Message "✓ Connection successful to $Server`:$Port" -Level "Success"
            return $true
        } else {
            Write-Log -Message "✗ Connection timeout to $Server`:$Port" -Level "Error"
            return $false
        }
    } catch {
        Write-Log -Message "✗ Connection failed: $_" -Level "Error"
        return $false
    } finally {
        $TcpClient.Dispose()
    }
}

# =============================================================================
# PHASE 1: PRE-MIGRATION SETUP
# =============================================================================

function Start-PreMigration {
    Write-Section "PHASE 1: PRE-MIGRATION SETUP"
    
    # Step 1: Launch Instance
    Write-Log -Message "Step 1: Launching EC2 instance from AMI..." -Level "Info"
    
    if ([string]::IsNullOrEmpty($AMI_ID)) {
        Write-Log -Message "ERROR: AMI_ID is required. Use -AMI_ID parameter" -Level "Error"
        return $false
    }
    
    if ([string]::IsNullOrEmpty($SubnetId)) {
        Write-Log -Message "ERROR: SubnetId is required. Use -SubnetId parameter" -Level "Error"
        return $false
    }
    
    try {
        $LaunchCommand = @(
            "aws ec2 run-instances",
            "--image-id $AMI_ID",
            "--instance-type $InstanceType",
            "--subnet-id $SubnetId",
            "--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=$ServerNameWithYear},{Key=Territory,Value=$Territory},{Key=Environment,Value=$Environment}]'",
            "--region $($Config.Region)"
        ) -join " "
        
        Write-Log -Message "Command: $LaunchCommand" -Level "Info"
        
        if (-not $DryRun) {
            $InstanceData = aws ec2 run-instances `
                --image-id $AMI_ID `
                --instance-type $InstanceType `
                --subnet-id $SubnetId `
                --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$ServerNameWithYear},{Key=Territory,Value=$Territory},{Key=Environment,Value=$Environment}]" `
                --region $Config.Region | ConvertFrom-Json
            
            $InstanceId = $InstanceData.Instances[0].InstanceId
            $PrivateIpAddress = $InstanceData.Instances[0].PrivateIpAddress
            
            Write-Log -Message "✓ Instance launched: $InstanceId (IP: $PrivateIpAddress)" -Level "Success"
            
            # Wait for instance to be running
            Write-Log -Message "Waiting for instance to reach running state..." -Level "Info"
            aws ec2 wait instance-running --instance-ids $InstanceId --region $Config.Region
            
            Write-Log -Message "✓ Instance is running" -Level "Success"
            
            # Save instance ID for later use
            $InstanceId | Out-File -FilePath (Join-Path $LogPath "InstanceId_$Territory.txt") -Force
        }
    } catch {
        Write-Log -Message "ERROR: Failed to launch instance: $_" -Level "Error"
        return $false
    }
    
    # Step 2: Configure Network
    Write-Log -Message "Step 2: Configuring network settings..." -Level "Info"
    Write-Log -Message "This step requires manual RDP connection or Systems Manager session" -Level "Warning"
    Write-Log -Message "Primary DNS: $($Config.Primary_DNS)" -Level "Info"
    Write-Log -Message "Secondary DNS: $($Config.Secondary_DNS)" -Level "Info"
    Write-Log -Message "Domain Suffix: $DomainName" -Level "Info"
    
    # Step 3: Disable Firewall
    Write-Log -Message "Step 3: Disable Windows Firewall (requires manual execution via RDP)" -Level "Info"
    
    # Step 4: Rename Computer
    Write-Log -Message "Step 4: Rename computer to $ServerNameWithYear (requires manual execution via RDP)" -Level "Info"
    
    # Step 5: Windows Updates
    Write-Log -Message "Step 5: Perform Windows Updates (requires manual execution)" -Level "Warning"
    
    Write-Log -Message "✓ Pre-migration phase initiated" -Level "Success"
    return $true
}

# =============================================================================
# PHASE 2: DURING ACTIVITY
# =============================================================================

function Start-DuringActivity {
    Write-Section "PHASE 2: DURING ACTIVITY"
    
    Write-Log -Message "Step 1: Verify old server is backed up..." -Level "Info"
    
    # Check for recent AMI
    try {
        $RecentAMIs = aws ec2 describe-images `
            --owners self `
            --query "sort_by(Images, &CreationDate)[-5:].{Name:Name,CreationDate:CreationDate,ImageId:ImageId}" `
            --region $Config.Region
        
        Write-Log -Message "Recent AMIs:" -Level "Info"
        Write-Log -Message $RecentAMIs -Level "Info"
    } catch {
        Write-Log -Message "WARNING: Could not list AMIs: $_" -Level "Warning"
    }
    
    Write-Log -Message "Step 2: Login to old server and cleanup DFS..." -Level "Warning"
    Write-Log -Message "This step requires manual execution" -Level "Info"
    
    Write-Log -Message "Step 3: Remove old server from domain..." -Level "Warning"
    
    Write-Log -Message "Step 4: Add Icinga downtime..." -Level "Info"
    
    Write-Log -Message "✓ During-activity phase initiated" -Level "Success"
    return $true
}

# =============================================================================
# PHASE 3: POST-MIGRATION CONFIGURATION
# =============================================================================

function Start-PostMigration {
    Write-Section "PHASE 3: POST-MIGRATION CONFIGURATION"
    
    Write-Log -Message "Step 1: Configure new server..." -Level "Info"
    
    # This would be executed on the new server via SSM or RDP
    $ConfigScript = @"
# Run as Administrator on new server
Write-Host "Configuring new server..."

# 1. Disable IPv6
Disable-NetAdapterBinding -Name "Ethernet" -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue

# 2. Configure DNS
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses @("$($Config.Primary_DNS)", "$($Config.Secondary_DNS)")
Set-DnsClient -InterfaceAlias "Ethernet" -ConnectionSpecificSuffix "$DomainName"

# 3. Set Timezone
Set-TimeZone -Name "$($Config.TimeZone)"

# 4. Disable Firewall
Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled `$false

# 5. Disable Windows Updates
Set-Service -Name wuauserv -StartupType Disabled
Stop-Service -Name wuauserv -ErrorAction SilentlyContinue

Write-Host "Configuration complete"
"@
    
    Write-Log -Message "Configuration script prepared" -Level "Info"
    
    # Step 2: Join domain
    Write-Log -Message "Step 2: Join domain $DomainName..." -Level "Warning"
    Write-Log -Message "This requires manual execution with domain credentials" -Level "Info"
    
    # Step 3: Move to OU
    Write-Log -Message "Step 3: Move server to OU: $($Config.OU_Path)" -Level "Info"
    
    # Step 4: Add to groups
    Write-Log -Message "Step 4: Add to security groups" -Level "Info"
    
    # Step 5: Configure DFS
    Write-Log -Message "Step 5: Configure DFS replication..." -Level "Info"
    
    Write-Log -Message "✓ Post-migration phase initiated" -Level "Success"
    return $true
}

# =============================================================================
# DOMAIN OPERATIONS
# =============================================================================

function Add-ServerToDomain {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        
        [Parameter(Mandatory=$true)]
        [string]$Domain,
        
        [Parameter(Mandatory=$false)]
        [PSCredential]$Credential
    )
    
    Write-Log -Message "Adding $ComputerName to domain $Domain..." -Level "Info"
    
    try {
        if ($null -eq $Credential) {
            $Credential = Get-Credential -Message "Enter domain admin credentials"
        }
        
        Add-Computer -DomainName $Domain -Credential $Credential -ComputerName $ComputerName -Force
        Write-Log -Message "✓ Server added to domain (reboot required)" -Level "Success"
        return $true
    } catch {
        Write-Log -Message "ERROR: Failed to add server to domain: $_" -Level "Error"
        return $false
    }
}

function Move-ServerToOU {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        
        [Parameter(Mandatory=$true)]
        [string]$OU_Path
    )
    
    Write-Log -Message "Moving $ComputerName to OU: $OU_Path..." -Level "Info"
    
    try {
        $Computer = Get-ADComputer -Identity $ComputerName
        Move-ADObject -Identity $Computer.ObjectGUID -TargetPath $OU_Path
        Write-Log -Message "✓ Server moved to OU" -Level "Success"
        return $true
    } catch {
        Write-Log -Message "ERROR: Failed to move server to OU: $_" -Level "Error"
        return $false
    }
}

function Add-ServerToSecurityGroup {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        
        [Parameter(Mandatory=$true)]
        [string]$GroupName
    )
    
    Write-Log -Message "Adding $ComputerName to group $GroupName..." -Level "Info"
    
    try {
        $Computer = Get-ADComputer -Identity $ComputerName
        Add-ADGroupMember -Identity $GroupName -Members $Computer
        Write-Log -Message "✓ Server added to security group" -Level "Success"
        return $true
    } catch {
        Write-Log -Message "ERROR: Failed to add server to group: $_" -Level "Error"
        return $false
    }
}

# =============================================================================
# AWS OPERATIONS
# =============================================================================

function Get-InstanceStatus {
    param([string]$InstanceId)
    
    Write-Log -Message "Getting instance status for $InstanceId..." -Level "Info"
    
    try {
        $Status = aws ec2 describe-instance-status `
            --instance-ids $InstanceId `
            --region $Config.Region | ConvertFrom-Json
        
        if ($Status.InstanceStatuses.Count -gt 0) {
            $State = $Status.InstanceStatuses[0].InstanceStatus.Status
            Write-Log -Message "Instance status: $State" -Level "Info"
            return $State
        }
    } catch {
        Write-Log -Message "WARNING: Could not get instance status: $_" -Level "Warning"
    }
}

function Create-AMIFromInstance {
    param([string]$InstanceId, [string]$ImageName)
    
    Write-Log -Message "Creating AMI from instance $InstanceId..." -Level "Info"
    
    try {
        if (-not $DryRun) {
            $ImageData = aws ec2 create-image `
                --instance-id $InstanceId `
                --name $ImageName `
                --description "Prepared server image - Territory: $Territory - Date: $(Get-Date -Format 'yyyy-MM-dd')" `
                --region $Config.Region | ConvertFrom-Json
            
            Write-Log -Message "✓ AMI created: $($ImageData.ImageId)" -Level "Success"
            $ImageData.ImageId | Out-File -FilePath (Join-Path $LogPath "AMI_ID_$Territory.txt") -Force
            return $ImageData.ImageId
        }
    } catch {
        Write-Log -Message "ERROR: Failed to create AMI: $_" -Level "Error"
        return $null
    }
}

function Terminate-Instance {
    param([string]$InstanceId)
    
    Write-Log -Message "Terminating instance $InstanceId..." -Level "Warning"
    
    try {
        if (-not $DryRun) {
            aws ec2 terminate-instances --instance-ids $InstanceId --region $Config.Region
            Write-Log -Message "✓ Instance termination initiated" -Level "Success"
            return $true
        }
    } catch {
        Write-Log -Message "ERROR: Failed to terminate instance: $_" -Level "Error"
        return $false
    }
}

# =============================================================================
# DFS OPERATIONS
# =============================================================================

function New-DFSReplicationGroup {
    param(
        [Parameter(Mandatory=$true)]
        [string]$GroupName,
        
        [Parameter(Mandatory=$false)]
        [string]$Description = "DFS Replication Group"
    )
    
    Write-Log -Message "Creating DFS replication group: $GroupName..." -Level "Info"
    
    try {
        New-DfsReplicationGroup -GroupName $GroupName -Description $Description
        Write-Log -Message "✓ DFS replication group created" -Level "Success"
        return $true
    } catch {
        Write-Log -Message "ERROR: Failed to create DFS replication group: $_" -Level "Error"
        return $false
    }
}

function Remove-DFSReplicationGroup {
    param([string]$GroupName)
    
    Write-Log -Message "Removing DFS replication group: $GroupName..." -Level "Warning"
    
    try {
        Remove-DfsReplicationGroup -GroupName $GroupName -RemoveReplicatedFolders -Force
        Write-Log -Message "✓ DFS replication group removed" -Level "Success"
        return $true
    } catch {
        Write-Log -Message "ERROR: Failed to remove DFS replication group: $_" -Level "Error"
        return $false
    }
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

function Main {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           SERVER MIGRATION AUTOMATION - Version $ScriptVersion                    ║" -ForegroundColor Cyan
    Write-Host "║        Territory: $Territory | Phase: $Phase | Environment: $Environment              ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log -Message "Script started" -ConsoleOnly
    Write-Log -Message "Territory: $Territory | Phase: $Phase | Environment: $Environment | Dry Run: $DryRun"
    
    # Validate territory
    if (-not $TerritoryConfig.ContainsKey($Territory)) {
        Write-Log -Message "ERROR: Invalid territory '$Territory'. Valid options: $(($TerritoryConfig.Keys) -join ', ')" -Level "Error"
        return
    }
    
    # Test prerequisites
    if (-not (Test-Prerequisites)) {
        Write-Log -Message "Prerequisites check failed. Aborting." -Level "Error"
        return
    }
    
    # Execute requested phases
    $Success = $true
    
    if ($Phase -eq "Pre" -or $Phase -eq "All") {
        if (-not (Start-PreMigration)) {
            $Success = $false
        }
    }
    
    if ($Phase -eq "During" -or $Phase -eq "All") {
        if (-not (Start-DuringActivity)) {
            $Success = $false
        }
    }
    
    if ($Phase -eq "Post" -or $Phase -eq "All") {
        if (-not (Start-PostMigration)) {
            $Success = $false
        }
    }
    
    Write-Host ""
    if ($Success) {
        Write-Log -Message "Script execution completed successfully" -Level "Success" -ConsoleOnly
        Write-Log -Message "Log file: $LogFile" -Level "Success" -ConsoleOnly
    } else {
        Write-Log -Message "Script execution completed with errors" -Level "Error" -ConsoleOnly
        Write-Log -Message "Log file: $LogFile" -Level "Error" -ConsoleOnly
    }
    Write-Host ""
}

# Execute main
Main
