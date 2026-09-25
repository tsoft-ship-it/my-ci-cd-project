# Server Migration Automation Suite

Complete PowerShell and AWS CLI automation for migrating XXSUPDFS01 → Territory-based XXSUPDEP01 servers across multiple regions.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Scripts](#scripts)
4. [Quick Start](#quick-start)
5. [Detailed Usage](#detailed-usage)
6. [Territory Configuration](#territory-configuration)
7. [Troubleshooting](#troubleshooting)
8. [Support](#support)

---

## Overview

This suite automates the complete server migration process across the following phases:

### Phase 1: Pre-Migration Setup
- Launch EC2 instance from AMI
- Configure network settings (DNS, IPv6, firewall)
- Apply Windows updates
- Create golden AMI image

### Phase 2: During Activity  
- Prepare old server for decommission
- Remove from domain and DFS
- Launch new server from prepared AMI
- Join domain and apply group policies

### Phase 3: Post-Migration
- Verify server configuration
- Configure DFS replication
- Add to security groups
- Update credentials and documentation

---

## Prerequisites

### Required Software
- **PowerShell 7+** (Windows Server 2022 or later)
- **AWS CLI v2** (for cloud operations)
- **Active Directory Module for PowerShell**
- **DFS Replication Tools**

### Required Permissions
- AWS: EC2, AMI, EBS permissions
- AD: Domain Admin rights
- Local: Administrator on Windows servers

### Required AWS Resources
- VPC with appropriate subnets
- Security groups configured
- AMI template image (XXSUPDFSXX)
- IAM credentials with EC2 permissions

---

## Scripts

### 1. `Migrate-Server-Complete.ps1`
**Main orchestration script** - Coordinates all phases

**Features:**
- Territory-based configuration
- Multi-phase execution
- Comprehensive logging
- Dry-run mode for validation
- AWS integration

**Usage:**
```powershell
.\Migrate-Server-Complete.ps1 -Territory "US" -Phase "Pre" `
    -AMI_ID "ami-12345678" -SubnetId "subnet-12345678"
```

**Parameters:**
```
-Territory      [US|EU|APAC|CA|AU]     Territory code (required)
-Phase          [Pre|During|Post|All]  Phase to execute (default: All)
-Environment    [Production|Staging]   Environment type
-AMI_ID         <string>               Source AMI ID
-InstanceType   <string>               EC2 instance type (default: m5.xlarge)
-SubnetId       <string>               Target subnet ID
-PrivateIP      <string>               Private IP address
-DryRun                                Show actions without executing
-Verbose                               Detailed output
```

**Example:**
```powershell
# Pre-migration setup for US territory
.\Migrate-Server-Complete.ps1 `
    -Territory "US" `
    -Phase "Pre" `
    -AMI_ID "ami-0c5d3e6c4b8a9f2e1" `
    -SubnetId "subnet-0a1b2c3d4e5f6g7h8" `
    -Environment "Production"

# Execute complete migration
.\Migrate-Server-Complete.ps1 -Territory "US" -Phase "All"
```

---

### 2. `Configure-NewServer.ps1`
**Server configuration script** - Run on newly launched instance

**Features:**
- Disable IPv6
- Configure DNS servers
- Set timezone
- Disable Windows Firewall
- Install Windows updates
- Disable Windows Update service
- Comprehensive verification

**Usage:**
```powershell
.\Configure-NewServer.ps1 -Territory "US" [-SkipUpdates] [-Restart]
```

**Parameters:**
```
-Territory      [US|EU|APAC|CA|AU]     Territory code (required)
-SkipUpdates                            Skip Windows Update installation
-Restart                                Restart system after configuration
```

**Run on Target Server:**
```powershell
# Via PowerShell remoting
$ServerName = "USSUPDFS01-2025"
Invoke-Command -ComputerName $ServerName -FilePath ".\Configure-NewServer.ps1" -ArgumentList "US"

# Or directly via RDP/Console
.\Configure-NewServer.ps1 -Territory "US" -Restart
```

---

### 3. `Configure-ActiveDirectory.ps1`
**Domain integration script** - Configure server AD settings

**Features:**
- Rename computer
- Join domain
- Move to correct OU
- Add to security groups
- Remove old server objects
- Update group policy
- Comprehensive AD verification

**Usage:**
```powershell
.\Configure-ActiveDirectory.ps1 -Territory "US" -ServerName "USSUPDEP01"
```

**Parameters:**
```
-Territory          [US|EU|APAC|CA|AU]     Territory code (required)
-ServerName         <string>               Computer name (required)
-Environment        [Production|Staging]   Environment
-DomainCredential   <PSCredential>         Domain admin credentials
-RemoveOldServer                           Delete old server from AD
-Restart                                   Restart after configuration
```

**Examples:**
```powershell
# Configure new server
.\Configure-ActiveDirectory.ps1 `
    -Territory "US" `
    -ServerName "USSUPDEP01" `
    -Environment "Production"

# Clean up - remove old server
.\Configure-ActiveDirectory.ps1 `
    -Territory "US" `
    -ServerName "USSUPDEP01" `
    -RemoveOldServer `
    -Restart
```

---

### 4. `Configure-DFSReplication.ps1`
**DFS replication setup script** - Configure file replication

**Features:**
- Create replication groups
- Add replication members
- Create replicated folders
- Configure connections
- Monitor replication status
- Automatic backlog checking

**Usage:**
```powershell
.\Configure-DFSReplication.ps1 -Territory "US" `
    -ReplicationGroup "IT-Support-Data-Transfer" `
    -ReplicationServers @("USSUPDEP01", "USSUPDEP02", "USSUPDEP03")
```

**Parameters:**
```
-Territory              [US|EU|APAC|CA|AU]     Territory code (required)
-ReplicationGroup       <string>               Group name (default: IT-Support-Data-Transfer)
-ReplicationServers     <string[]>             Server list
-ReplicationPath        <string>               Content path (default: D:\ReplicationData)
-RemoveOldGroup                                Remove existing group first
-Force                                         Skip confirmations
```

**Examples:**
```powershell
# Setup new DFS group with default servers
.\Configure-DFSReplication.ps1 -Territory "US"

# Custom server list
.\Configure-DFSReplication.ps1 `
    -Territory "EU" `
    -ReplicationServers @("EUSUPDEP01", "EUSUPDEP02") `
    -RemoveOldGroup

# Monitor replication
Get-DfsReplicationGroupMembership -GroupName "IT-Support-Data-Transfer" -FolderName "IT-Support-Data" | 
    Get-DfsReplicationGroupMembershipHealth
```

---

### 5. `AWS-ServerMigration.sh`
**AWS CLI wrapper** - EC2 instance operations

**Features:**
- Launch instances
- Check status
- Create AMIs
- Terminate instances
- List instances
- Comprehensive logging
- Dry-run mode

**Usage:**
```bash
./AWS-ServerMigration.sh --territory US --action launch \
    --ami-id ami-12345678 --subnet-id subnet-12345678
```

**Parameters:**
```
-t, --territory         [US|EU|APAC|CA|AU]   Territory code
-a, --action           [launch|status|create-ami|terminate|list]
-i, --instance-id      <string>             EC2 instance ID
-m, --ami-id           <string>             AMI ID
-s, --subnet-id        <string>             Subnet ID
-n, --instance-name    <string>             Instance name
-z, --instance-type    <string>             Instance type (default: m5.xlarge)
-p, --private-ip       <string>             Private IP address
--environment          [Production|Staging]
--dry-run                                   Show what would be done
-v, --verbose                               Verbose output
```

**Examples:**
```bash
# Launch instance
./AWS-ServerMigration.sh \
    --territory US \
    --action launch \
    --ami-id ami-0c5d3e6c4b8a9f2e1 \
    --subnet-id subnet-0a1b2c3d4e5f6g7h8 \
    --instance-name USSUPDFS01-2025 \
    --private-ip 10.1.0.40

# Check instance status
./AWS-ServerMigration.sh \
    --territory US \
    --action status \
    --instance-id i-0123456789abcdef0

# Create AMI
./AWS-ServerMigration.sh \
    --territory US \
    --action create-ami \
    --instance-id i-0123456789abcdef0

# List all instances
./AWS-ServerMigration.sh --territory US --action list

# Terminate instance (with confirmation)
./AWS-ServerMigration.sh \
    --territory US \
    --action terminate \
    --instance-id i-0123456789abcdef0
```

**Make script executable:**
```bash
chmod +x AWS-ServerMigration.sh
```

---

## Quick Start

### 1. Prepare Environment

```powershell
# Clone/download scripts
git clone <repository>
cd server-migration

# Verify prerequisites
$PSVersionTable.PSVersion  # Should be 7.0+
aws --version              # Should be 2.0+
aws configure              # Setup AWS credentials
```

### 2. Pre-Migration (Week Before)

```powershell
# Launch preparation instance
.\Migrate-Server-Complete.ps1 `
    -Territory "US" `
    -Phase "Pre" `
    -AMI_ID "ami-0c5d3e6c4b8a9f2e1" `
    -SubnetId "subnet-0a1b2c3d4e5f6g7h8" `
    -Environment "Production"

# RDP into instance and run configuration
.\Configure-NewServer.ps1 -Territory "US"

# Monitor logs
Get-Content "logs\Migration_US_*.log" -Tail 20
```

### 3. During Migration (Cutover Window)

```powershell
# Start during-activity phase
.\Migrate-Server-Complete.ps1 `
    -Territory "US" `
    -Phase "During" `
    -Environment "Production"

# Wait for final verification
.\Configure-ActiveDirectory.ps1 `
    -Territory "US" `
    -ServerName "USSUPDEP01" `
    -RemoveOldServer
```

### 4. Post-Migration (After Cutover)

```powershell
# Configure DFS replication
.\Configure-DFSReplication.ps1 -Territory "US"

# Verify all systems
.\Migrate-Server-Complete.ps1 `
    -Territory "US" `
    -Phase "Post" `
    -Environment "Production"
```

---

## Detailed Usage

### AWS Operations

#### Launch New Instance
```bash
./AWS-ServerMigration.sh \
    --territory US \
    --action launch \
    --ami-id ami-0c5d3e6c4b8a9f2e1 \
    --subnet-id subnet-0a1b2c3d4e5f6g7h8 \
    --instance-type m5.xlarge \
    --private-ip 10.1.0.40 \
    --instance-name USSUPDFS01-2025

# Output will save Instance ID to: logs/instance_id_US.txt
INSTANCE_ID=$(cat logs/instance_id_US.txt)
```

#### Monitor Instance
```bash
./AWS-ServerMigration.sh \
    --territory US \
    --action status \
    --instance-id i-0123456789abcdef0
```

#### Create Backup AMI
```bash
./AWS-ServerMigration.sh \
    --territory US \
    --action create-ami \
    --instance-id i-0123456789abcdef0

# Saves AMI ID to: logs/ami_id_US.txt
AMI_ID=$(cat logs/ami_id_US.txt)
```

#### Terminate Old Instance
```bash
./AWS-ServerMigration.sh \
    --territory US \
    --action terminate \
    --instance-id i-0987654321fedcba0
```

### Server Configuration

#### Initial Setup (Run on new instance)
```powershell
# Via RDP/Console on new server:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
.\Configure-NewServer.ps1 -Territory "US"
```

#### Domain Integration (Run from domain controller or joined machine)
```powershell
# From management workstation:
.\Configure-ActiveDirectory.ps1 `
    -Territory "US" `
    -ServerName "USSUPDEP01" `
    -DomainCredential (Get-Credential)
```

#### DFS Replication (Run on designated DFS server)
```powershell
# Create new replication group
.\Configure-DFSReplication.ps1 `
    -Territory "US" `
    -ReplicationGroup "IT-Support-Data-Transfer" `
    -ReplicationServers @("USSUPDEP01", "USSUPDEP02", "USSUPDEP03")

# Monitor status
$Group = Get-DfsReplicationGroup -GroupName "IT-Support-Data-Transfer"
$Group | Get-DfsReplicationGroupConnection | Format-Table
$Group | Get-DfsReplicatedFolder
```

### Logging & Monitoring

#### View Logs
```powershell
# Main migration log
Get-Content "logs\Migration_US_*.log"

# Configuration transcript
Get-Content "logs\Configuration_*.txt"

# DFS configuration log
Get-Content "logs\DFSConfiguration_*.txt"

# AWS operations log
tail -f logs/aws_migration_*.log
```

#### Search Logs
```powershell
# Find errors
Select-String "ERROR" logs\*.log

# Find specific server references
Select-String "USSUPDEP01" logs\*.log

# Get summary
(Get-Content logs\Migration_US_*.log | Measure-Object -Line).Lines
```

---

## Territory Configuration

### Supported Territories

#### US (United States)
```powershell
Territory Code:    US
Region:            us-east-1
VPC CIDR:          10.1.0.0/16
Primary DNS:       10.1.1.10
Secondary DNS:     10.1.1.20
Domain:            company.local
Timezone:          Central Standard Time
OU Path:           OU=Deployment Servers,OU=Servers,OU=Resources,DC=company,DC=local
```

#### EU (Europe)
```powershell
Territory Code:    EU
Region:            eu-west-1
VPC CIDR:          10.2.0.0/16
Primary DNS:       10.2.1.10
Secondary DNS:     10.2.1.20
Domain:            eu.company.local
Timezone:          Romance Standard Time
OU Path:           OU=Deployment Servers,OU=Servers,OU=Resources,DC=eu,DC=company,DC=local
```

#### APAC (Asia-Pacific)
```powershell
Territory Code:    APAC
Region:            ap-southeast-1
VPC CIDR:          10.3.0.0/16
Primary DNS:       10.3.1.10
Secondary DNS:     10.3.1.20
Domain:            apac.company.local
Timezone:          Singapore Standard Time
OU Path:           OU=Deployment Servers,OU=Servers,OU=Resources,DC=apac,DC=company,DC=local
```

#### CA (Canada)
```powershell
Territory Code:    CA
Region:            ca-central-1
VPC CIDR:          10.4.0.0/16
Primary DNS:       10.4.1.10
Secondary DNS:     10.4.1.20
Domain:            ca.company.local
Timezone:          Eastern Standard Time
OU Path:           OU=Deployment Servers,OU=Servers,OU=Resources,DC=ca,DC=company,DC=local
```

#### AU (Australia)
```powershell
Territory Code:    AU
Region:            ap-southeast-2
VPC CIDR:          10.5.0.0/16
Primary DNS:       10.5.1.10
Secondary DNS:     10.5.1.20
Domain:            au.company.local
Timezone:          AUS Eastern Standard Time
OU Path:           OU=Deployment Servers,OU=Servers,OU=Resources,DC=au,DC=company,DC=local
```

### Customizing Configuration

Edit the `$TerritoryConfig` hashtable in each script to add new territories or modify existing settings.

---

## Troubleshooting

### DNS Configuration Issues

```powershell
# Verify DNS servers
Get-DnsClientServerAddress -AddressFamily IPv4
Get-DnsClient

# Manually set DNS
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" `
    -ServerAddresses @("10.1.1.10", "10.1.1.20")

# Test DNS resolution
Resolve-DnsName company.local
```

### Domain Join Failures

```powershell
# Test domain connectivity
Test-ComputerSecureChannel -Credential (Get-Credential)

# Verify network settings
Get-NetAdapter
Get-NetRoute

# Check domain trust
nltest /sc_query:company.local

# Rejoin domain
Remove-Computer -UnjoinDomainCredential (Get-Credential) -Restart
Add-Computer -DomainName company.local -Credential (Get-Credential) -Restart
```

### AWS Connectivity Issues

```bash
# Test AWS credentials
aws sts get-caller-identity

# Check EC2 permissions
aws ec2 describe-instances --region us-east-1

# Verify security group rules
aws ec2 describe-security-groups --region us-east-1

# Check VPC connectivity
aws ec2 describe-vpcs --region us-east-1
```

### DFS Replication Issues

```powershell
# Check DFS service status
Get-Service DFSR | Select-Object Status, StartType

# Monitor replication
Get-DfsReplicationGroup | Get-DfsReplicationGroupMembership | 
    Get-DfsReplicationGroupMembershipHealth | Format-Table

# View DFS events
Get-EventLog -LogName "DFS Replication" -Newest 50

# Force replication update
Invoke-DfsrPropagationTestEvent -GroupName "IT-Support-Data-Transfer" `
    -FolderName "IT-Support-Data" `
    -ReferenceComputerName "USSUPDEP01"
```

### Firewall Issues

```powershell
# Check firewall status
Get-NetFirewallProfile

# Disable firewall (if required)
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled $false

# Allow specific ports
New-NetFirewallRule -DisplayName "Allow RDP" -Direction Inbound `
    -LocalPort 3389 -Protocol TCP -Action Allow

# View active rules
Get-NetFirewallRule -Enabled $true | Format-Table
```

### Script Errors

**Error: "AWS credentials not configured"**
```bash
aws configure
# Enter AWS Access Key ID
# Enter AWS Secret Access Key
# Enter Default region
# Enter Default output format (json)
```

**Error: "Script cannot be loaded because running scripts is disabled"**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

**Error: "Access Denied" on AD operations**
```powershell
# Run as Administrator
Start-Process powershell -ArgumentList '-NoExit', '-Command', '.\Configure-ActiveDirectory.ps1 -Territory US -ServerName USSUPDEP01' -Verb RunAs
```

---

## Support

### Log Files Location
- **Main logs:** `./logs/Migration_*.log`
- **Configuration:** `./logs/Configuration_*.txt`
- **DFS:** `./logs/DFSConfiguration_*.txt`
- **AWS:** `./logs/aws_migration_*.log`

### Debug Mode
```powershell
# Enable verbose output
$VerbosePreference = "Continue"
.\Migrate-Server-Complete.ps1 -Territory "US" -Verbose

# Enable debug output
$DebugPreference = "Continue"
```

### Getting Help
```powershell
# Script help
Get-Help .\Migrate-Server-Complete.ps1 -Full
Get-Help .\Configure-NewServer.ps1 -Full
Get-Help .\Configure-ActiveDirectory.ps1 -Full

# AWS CLI help
./AWS-ServerMigration.sh --help
./AWS-ServerMigration.sh -h
```

### Contact Information
For issues or questions:
1. Check logs in `./logs/` directory
2. Review this README.md
3. Verify prerequisites are installed
4. Contact Infrastructure team with:
   - Territory code
   - Instance ID
   - Error message
   - Log file excerpt

---

## Version History

**v1.0.0** (Current)
- Initial release
- Support for 5 territories (US, EU, APAC, CA, AU)
- Complete pre/during/post migration automation
- DFS replication configuration
- Comprehensive logging and error handling

---

## License

© 2025 Your Organization. All rights reserved.

---

**Last Updated:** 2025-09-25  
**Script Version:** 1.0.0  
**PowerShell Version:** 7.0+  
**AWS CLI Version:** 2.0+
