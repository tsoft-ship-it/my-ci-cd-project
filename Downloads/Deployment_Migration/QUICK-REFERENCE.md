# Server Migration - Quick Reference Guide

Fast access to common commands and scenarios.

---

## Common Commands

### Launch New Server (US Territory)
```powershell
.\Migrate-Server-Complete.ps1 `
    -Territory "US" `
    -Phase "Pre" `
    -AMI_ID "ami-0c5d3e6c4b8a9f2e1" `
    -SubnetId "subnet-0a1b2c3d4e5f6g7h8"
```

### Configure New Server (After RDP Connection)
```powershell
# On the new instance (run as Administrator)
.\Configure-NewServer.ps1 -Territory "US" -Restart
```

### Join Domain
```powershell
# From management machine (as Administrator)
.\Configure-ActiveDirectory.ps1 `
    -Territory "US" `
    -ServerName "USSUPDEP01"
```

### Setup DFS Replication
```powershell
# On DFS server (run as Administrator)
.\Configure-DFSReplication.ps1 -Territory "US"
```

### Check AWS Instance
```bash
./AWS-ServerMigration.sh --territory US --action status --instance-id i-0123456789abcdef0
```

### Create AMI Backup
```bash
./AWS-ServerMigration.sh --territory US --action create-ami --instance-id i-0123456789abcdef0
```

---

## Step-by-Step Runbook

### 1. Launch Phase (Monday 8 AM)

```powershell
# Step 1: Launch instance in AWS
./AWS-ServerMigration.sh `
    --territory US `
    --action launch `
    --ami-id ami-0c5d3e6c4b8a9f2e1 `
    --subnet-id subnet-0a1b2c3d4e5f6g7h8 `
    --instance-name USSUPDFS01-2025

# Step 2: Note the Instance ID
$InstanceId = cat logs/instance_id_US.txt

# Step 3: Wait for running state
Start-Sleep -Seconds 60
./AWS-ServerMigration.sh --territory US --action status --instance-id $InstanceId

# Step 4: RDP into instance (Windows key + R, mstsc)
# Connect to: <Private IP from step 3>
# Username: Administrator (use local creds from AMI)
```

### 2. Configure Phase (Monday 9 AM - 12 PM)

```powershell
# Step 1: Run from RDP session on new instance (as Administrator)
.\Configure-NewServer.ps1 -Territory "US"

# Step 2: Review configuration output
# Verify:
# - IPv6 disabled
# - DNS set to 10.1.1.10 and 10.1.1.20
# - Timezone: Central Standard Time
# - Firewall: Disabled
# - Windows Update Service: Disabled

# Step 3: Rename computer (will reboot)
Rename-Computer -NewName "USSUPDFS01" -Restart

# Step 4: Wait 5 minutes for reboot
Start-Sleep -Seconds 300
```

### 3. Prepare Old Server (Monday 1 PM)

```powershell
# Step 1: Connect to old server
# RDP to USSUPDEP01

# Step 2: Backup current configuration
Get-DfsReplicationGroup | Export-Clixml D:\DFS_Backup.xml

# Step 3: Remove DFS replication group
Remove-DfsReplicationGroup -GroupName "IT-Support-Data-Transfer" -RemoveReplicatedFolders

# Step 4: Remove from domain
Remove-Computer -UnjoinDomainCredential (Get-Credential) -Force -Restart

# Step 5: After reboot, rename server
Rename-Computer -NewName "USSUPDEP01-OLD" -Restart
```

### 4. Migration Phase (Monday 3 PM)

```bash
# Step 1: Shutdown old server
./AWS-ServerMigration.sh --territory US --action terminate --instance-id i-old123456

# Step 2: Launch new server from prepared AMI
./AWS-ServerMigration.sh `
    --territory US `
    --action launch `
    --ami-id ami-prepared789 `
    --subnet-id subnet-0a1b2c3d4e5f6g7h8 `
    --instance-name USSUPDEP01 `
    --private-ip 10.1.0.40

# Step 3: Wait for running
sleep 30

# Step 4: RDP into new server
# Username: Administrator
# Password: [from prepared image]
```

### 5. Domain Phase (Monday 4 PM)

```powershell
# Step 1: From management machine
.\Configure-ActiveDirectory.ps1 `
    -Territory "US" `
    -ServerName "USSUPDEP01"

# Step 2: At reboot prompts, press Enter to accept
# (System will reboot twice)

# Step 3: Wait 5 minutes after final reboot

# Step 4: Verify domain join
whoami  # Should show: COMPANY\USSUPDEP01$
```

### 6. DFS Phase (Monday 5 PM)

```powershell
# Step 1: Configure DFS on new server (run as Administrator)
.\Configure-DFSReplication.ps1 -Territory "US"

# Step 2: Monitor replication
Get-DfsReplicationGroup -GroupName "IT-Support-Data-Transfer" | 
    Get-DfsReplicationGroupMembership | 
    Get-DfsReplicationGroupMembershipHealth

# Step 3: Check Event Viewer
# Events > Windows Logs > System (should see DFS events)
```

### 7. Verification Phase (Monday 6 PM)

```powershell
# Step 1: Verify network
Test-NetConnection -ComputerName USSUPDEP01 -Port 3389
Resolve-DnsName USSUPDEP01.company.local

# Step 2: Verify services
Get-Service wuauserv | Select Status, StartType  # Should be Stopped, Disabled
Get-NetFirewallProfile | Select Name, Enabled    # Should all be False

# Step 3: Verify DFS status
Get-DfsReplicationGroup | Get-DfsReplicatedFolder
Get-DfsReplicationGroup | Get-DfsReplicationGroupConnection

# Step 4: Verify Icinga downtime is removed
# (Remove in Icinga web UI or CLI)

# Step 5: Send completion email
# To: IT Leadership
# Subject: USSUPDEP01 Migration Complete - US Territory
# Body: New server live at 10.1.0.40, old server terminated
```

---

## DNS Cheat Sheet

### Verify DNS Settings
```powershell
# Check what DNS is being used
Get-DnsClientServerAddress -AddressFamily IPv4

# Test DNS resolution
Resolve-DnsName company.local
Resolve-DnsName USSUPDEP01.company.local

# Flush DNS cache
Clear-DnsClientCache

# Set DNS servers
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" `
    -ServerAddresses @("10.1.1.10", "10.1.1.20")
```

### By Territory
```powershell
# US Territory
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses @("10.1.1.10", "10.1.1.20")

# EU Territory
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses @("10.2.1.10", "10.2.1.20")

# APAC Territory
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses @("10.3.1.10", "10.3.1.20")
```

---

## Active Directory Cheat Sheet

### Check Domain Status
```powershell
# Verify domain membership
Get-ADComputer -Identity USSUPDEP01

# Check group membership
Get-ADPrincipalGroupMembership -Identity USSUPDEP01

# Verify OU placement
(Get-ADComputer -Identity USSUPDEP01).DistinguishedName

# Force GPO update
Gpupdate /force /sync
```

### Move Server in OU
```powershell
# Move to correct OU
$Computer = Get-ADComputer -Identity USSUPDEP01
Move-ADObject -Identity $Computer.ObjectGUID `
    -TargetPath "OU=Deployment Servers,OU=Servers,OU=Resources,DC=company,DC=local"
```

### Add to Security Groups
```powershell
# Add to groups
Add-ADGroupMember -Identity "ROLE-GPO_CENTRAL-SERVER" -Members (Get-ADComputer USSUPDEP01)
Add-ADGroupMember -Identity "ROLE-SERVER-ADMINS" -Members (Get-ADComputer USSUPDEP01)

# Verify membership
Get-ADPrincipalGroupMembership -Identity USSUPDEP01 | Sort-Object Name
```

---

## DFS Cheat Sheet

### Check DFS Status
```powershell
# List replication groups
Get-DfsReplicationGroup

# Get group members
Get-DfsReplicationGroup -GroupName "IT-Support-Data-Transfer" | Get-DfsReplicationGroupMember

# Check connections
Get-DfsReplicationGroup -GroupName "IT-Support-Data-Transfer" | Get-DfsReplicationGroupConnection

# Get replication status
Get-DfsReplicationGroup -GroupName "IT-Support-Data-Transfer" | 
    Get-DfsReplicationGroupMembership | 
    Get-DfsReplicationGroupMembershipHealth | 
    Format-Table ComputerName, FolderName, State, Health
```

### Monitor DFS Backlog
```powershell
# Check replication backlog
Get-DfsReplicationGroupMembership `
    -GroupName "IT-Support-Data-Transfer" `
    -FolderName "IT-Support-Data" | 
    Get-DfsReplicationGroupMembershipHealth

# Monitor in real-time
while ($true) {
    Clear-Host
    Get-DfsReplicationGroup | 
        Get-DfsReplicationGroupMembership | 
        Get-DfsReplicationGroupMembershipHealth | 
        Format-Table
    Start-Sleep -Seconds 10
}
```

### View DFS Events
```powershell
# Get recent DFS events
Get-EventLog -LogName "DFS Replication" -Newest 20

# Filter for errors
Get-EventLog -LogName "DFS Replication" -EntryType Error | Format-List

# Export to file
Get-EventLog -LogName "DFS Replication" -Newest 100 | Export-Csv DFS_Events.csv
```

---

## AWS Cheat Sheet

### List Instances
```bash
# List all instances in region
aws ec2 describe-instances --region us-east-1

# List by territory tag
aws ec2 describe-instances \
    --filters "Name=tag:Territory,Values=US" \
    --region us-east-1

# Format as table
aws ec2 describe-instances \
    --filters "Name=tag:Territory,Values=US" \
    --query 'Reservations[].Instances[].[InstanceId, State.Name, InstanceType, PrivateIpAddress, Tags[?Key==`Name`].Value|[0]]' \
    --output table \
    --region us-east-1
```

### Get Instance Details
```bash
# Get specific instance info
aws ec2 describe-instances \
    --instance-ids i-0123456789abcdef0 \
    --region us-east-1 \
    --output json

# Get just the IP
aws ec2 describe-instances \
    --instance-ids i-0123456789abcdef0 \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text \
    --region us-east-1
```

### Create/Delete Resources
```bash
# Create AMI
aws ec2 create-image \
    --instance-id i-0123456789abcdef0 \
    --name "USSUPDFS01-Prepared-$(date +%Y%m%d)" \
    --region us-east-1

# Create tags
aws ec2 create-tags \
    --resources i-0123456789abcdef0 \
    --tags Key=Name,Value=USSUPDEP01 Key=Territory,Value=US \
    --region us-east-1

# Terminate instance
aws ec2 terminate-instances \
    --instance-ids i-0123456789abcdef0 \
    --region us-east-1
```

---

## Firewall Rules

### Disable Firewall (Simple)
```powershell
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled $false
```

### Enable Specific Ports (Alternative)
```powershell
# Enable RDP
New-NetFirewallRule -DisplayName "Allow RDP" -Direction Inbound `
    -LocalPort 3389 -Protocol TCP -Action Allow

# Enable WinRM (if using remote PowerShell)
Enable-PSRemoting -Force

# Enable file sharing (DFS)
New-NetFirewallRule -DisplayName "Allow DFS" -Direction Inbound `
    -LocalPort 445 -Protocol TCP -Action Allow
```

### View Firewall Rules
```powershell
# List all rules
Get-NetFirewallRule -Enabled $true | Format-Table

# List RDP rules
Get-NetFirewallRule -DisplayName "*RDP*"

# List file sharing
Get-NetFirewallRule -DisplayName "*SMB*"
```

---

## Logging & Debugging

### View Recent Logs
```powershell
# Last 50 lines of migration log
tail -f logs/Migration_US_*.log

# Search for errors
Select-String "ERROR" logs/*.log

# Get summary stats
$Log = Get-Content logs/Migration_US_*.log
Write-Host "Total lines: $($Log.Count)"
Write-Host "Errors: $(($Log | Select-String 'ERROR').Count)"
Write-Host "Warnings: $(($Log | Select-String 'WARNING').Count)"
Write-Host "Success: $(($Log | Select-String 'SUCCESS').Count)"
```

### Enable Debug Output
```powershell
# Verbose
$VerbosePreference = "Continue"
.\Configure-NewServer.ps1 -Territory "US" -Verbose

# Debug
$DebugPreference = "Continue"
.\Configure-ActiveDirectory.ps1 -Territory "US" -ServerName USSUPDEP01 -Debug

# Both
$VerbosePreference = "Continue"
$DebugPreference = "Continue"
```

---

## Emergency Procedures

### Rollback to Old Server
```powershell
# If new server fails, revert:

# 1. Shutdown new server
Stop-Computer -ComputerName USSUPDEP01 -Force

# 2. Reboot old server (USSUPDEP01-OLD)
# 3. Rejoin to domain
Add-Computer -DomainName company.local -Credential (Get-Credential) -Restart

# 4. Restore DFS config
Import-Clixml D:\DFS_Backup.xml

# 5. Force GPO update
Gpupdate /force /sync
```

### Emergency Access
```powershell
# If domain auth fails, use local admin:
# In RDP connect dialog: .\Administrator (backslash means local)

# Reset local admin password
net user Administrator NewPassword123!

# Check local admin account
Get-LocalUser -Name Administrator

# Enable disabled admin account
Enable-LocalUser -Name Administrator
```

### Network Troubleshooting
```powershell
# Test connectivity
Test-NetConnection -ComputerName 10.1.0.40
Test-NetConnection -ComputerName USSUPDEP01 -Port 3389

# View network config
ipconfig /all

# Reset network
ipconfig /release
ipconfig /renew

# View routing table
Get-NetRoute

# Flush DNS
ipconfig /flushdns
```

---

## Completion Checklist

- [ ] New instance launched and running
- [ ] DNS configured correctly
- [ ] Windows Firewall disabled
- [ ] Windows Updates installed
- [ ] Computer renamed
- [ ] Server joined to domain
- [ ] Moved to correct OU
- [ ] Added to security groups
- [ ] GPO updated
- [ ] DFS replication configured
- [ ] Replication status healthy
- [ ] Old server removed from domain
- [ ] Old server terminated in AWS
- [ ] Icinga downtime removed
- [ ] Bitwarden credentials updated
- [ ] Team notification sent
- [ ] Logs archived

---

## Territory Quick Reference

| Code | Region | DNS Primary | DNS Secondary | Domain | TZ |
|------|--------|-------------|---------------|--------|-----|
| US | us-east-1 | 10.1.1.10 | 10.1.1.20 | company.local | Central |
| EU | eu-west-1 | 10.2.1.10 | 10.2.1.20 | eu.company.local | Romance |
| APAC | ap-southeast-1 | 10.3.1.10 | 10.3.1.20 | apac.company.local | Singapore |
| CA | ca-central-1 | 10.4.1.10 | 10.4.1.20 | ca.company.local | Eastern |
| AU | ap-southeast-2 | 10.5.1.10 | 10.5.1.20 | au.company.local | AUS Eastern |

---

## Contact & Support

**Issues?** Check:
1. Logs in `./logs/` 
2. DNS settings (most common issue)
3. Firewall rules (second most common)
4. Domain credentials (third most common)

**Can't connect?**
- Verify IP address: `ipconfig /all`
- Test connectivity: `ping 10.1.1.10`
- Check firewall: `Get-NetFirewallProfile`

**Need rollback?**
- See Emergency Procedures section
- Restore from AWS snapshot if available
- Re-launch from previous AMI

---

**Updated:** 2025-09-25  
**Version:** 1.0.0
