# Server Migration - Deployment Checklist
## Territory: ________  |  Date: ________  |  Team Lead: ________

---

## PRE-MIGRATION VERIFICATION (Day Before)

### Environment Readiness
- [ ] AWS credentials configured and tested
- [ ] PowerShell execution policy set to RemoteSigned
- [ ] All scripts downloaded and verified
- [ ] Log directory created: `./logs/`
- [ ] Territory configuration reviewed and correct
- [ ] AMI ID confirmed and accessible
- [ ] Subnet ID confirmed and accessible
- [ ] Security groups identified and ready

### Prerequisites Check
- [ ] PowerShell 7.0+ installed
- [ ] AWS CLI v2 installed
- [ ] Active Directory connectivity verified
- [ ] DFS Replication service installed (if needed)
- [ ] Network connectivity to DNS servers tested
- [ ] Backup credentials stored in secure location
- [ ] Domain admin credentials prepared
- [ ] Old server backed up to storage

### Team Communication
- [ ] Change request submitted and approved
- [ ] Maintenance window scheduled
- [ ] Stakeholders notified of downtime
- [ ] Rollback plan documented
- [ ] Emergency contacts list prepared
- [ ] Icinga maintenance window requested

---

## PHASE 1: LAUNCH & PREPARE (8:00 AM - 12:00 PM)

### Step 1: Launch Instance
- [ ] Run: `.\Migrate-Server-Complete.ps1 -Territory "XX" -Phase "Pre"`
- [ ] Instance ID: `_____________________`
- [ ] Private IP: `_____________________`
- [ ] Confirm instance in AWS console
- [ ] Instance state: **running** ✓
- [ ] Verify security groups applied
- [ ] Verify tags applied correctly

### Step 2: Connect to New Instance
- [ ] Wait 2 minutes for Windows startup
- [ ] RDP to: `_____________________`
- [ ] Username: `Administrator`
- [ ] Password: `_____________________`
- [ ] Connection successful ✓

### Step 3: Configure Network
- [ ] Run: `.\Configure-NewServer.ps1 -Territory "XX"`
- [ ] Script execution completed ✓
- [ ] Transcript saved: `C:\Logs\Configuration_*.txt`
- [ ] Review configuration output
  - [ ] IPv6 disabled
  - [ ] DNS configured correctly
  - [ ] Timezone set correctly
  - [ ] Firewall disabled
  - [ ] Windows Update service disabled

### Step 4: Rename Computer
- [ ] Run: `Rename-Computer -NewName "XXSUPDFS01" -Restart`
- [ ] Verify computer renamed ✓
- [ ] Computer restarted successfully ✓

### Step 5: Windows Updates
- [ ] Install all critical updates
- [ ] All updates completed ✓
- [ ] Update count: `_____________________`
- [ ] No pending reboot required ✓

### Step 6: Create AMI
- [ ] Run: `./AWS-ServerMigration.sh --territory XX --action create-ami --instance-id i-xxxxxxxxx`
- [ ] AMI creation initiated ✓
- [ ] AMI ID: `_____________________`
- [ ] Wait for AMI completion (10-20 minutes)
- [ ] AMI available in console ✓
- [ ] Verify tags on AMI ✓

### Step 7: Terminate Preparation Instance
- [ ] Run: `./AWS-ServerMigration.sh --territory XX --action terminate --instance-id i-xxxxxxxxx`
- [ ] Termination initiated ✓
- [ ] Instance terminated in console ✓

**End of Phase 1 - Pause here until cutover window begins**

---

## PHASE 2: DURING ACTIVITY (1:00 PM - 3:00 PM)

### Pre-Cutover Tasks
- [ ] Daily backup completed
- [ ] Backup AMI of old server exists ✓
- [ ] All team members ready
- [ ] Icinga downtime window activated
- [ ] Change ticket updated with progress

### Step 1: Prepare Old Server
- [ ] Connect to old server (XXSUPDEP01)
- [ ] Backup DFS configuration: `Export-Clixml D:\DFS_Backup.xml`
- [ ] Remove DFS replication group
  - Command executed ✓
  - Confirmation: `_____________________`
- [ ] Verify DFS removed ✓

### Step 2: Remove Old Server from Domain
- [ ] Run: `Remove-Computer -UnjoinDomainCredential (Get-Credential) -Force -Restart`
- [ ] Old server removed from domain ✓
- [ ] System restarted ✓

### Step 3: Rename Old Server
- [ ] Run: `Rename-Computer -NewName "XXSUPDEP01-OLD" -Restart`
- [ ] Computer renamed to: `XXSUPDEP01-OLD` ✓
- [ ] System restarted ✓

### Step 4: Terminate Old Server in AWS
- [ ] Run: `./AWS-ServerMigration.sh --territory XX --action terminate --instance-id i-old`
- [ ] Termination initiated ✓
- [ ] Verified in AWS console ✓
- [ ] Termination time: `_____________________`

### Step 5: Launch New Server from AMI
- [ ] Run: `./AWS-ServerMigration.sh --territory XX --action launch --ami-id ami-xxxxxxxx --subnet-id subnet-xxxxx --private-ip 10.XX.0.40`
- [ ] New instance launched ✓
- [ ] Instance ID: `_____________________`
- [ ] Private IP: `10.XX.0.40` ✓
- [ ] Wait for running state
- [ ] Instance is running ✓

### Step 6: Initial Verification
- [ ] Test connectivity: `Test-NetConnection -ComputerName 10.XX.0.40 -Port 3389`
- [ ] Connection successful ✓
- [ ] RDP to new server successful ✓

**End of Phase 2 - Critical cutover point complete**

---

## PHASE 3: DOMAIN INTEGRATION (3:00 PM - 4:30 PM)

### Step 1: Verify Network Configuration
- [ ] Check DNS settings: `Get-DnsClientServerAddress -AddressFamily IPv4`
- [ ] Primary DNS: `10.XX.1.10` ✓
- [ ] Secondary DNS: `10.XX.1.20` ✓
- [ ] Test DNS: `Resolve-DnsName company.local`
- [ ] DNS resolution working ✓

### Step 2: Configure Active Directory
- [ ] Run (from management machine): `.\Configure-ActiveDirectory.ps1 -Territory "XX" -ServerName "XXSUPDEP01"`
- [ ] Script execution started ✓
- [ ] At prompts, accept defaults
- [ ] System rebooted automatically ✓
- [ ] Wait 2 minutes for second reboot
- [ ] Final reboot completed ✓
- [ ] Wait 5 minutes for group policies to apply

### Step 3: Verify Domain Join
- [ ] Connect to new server via RDP
- [ ] Run: `whoami /upn`
- [ ] Should show: `XXSUPDEP01$@company.local` (or similar)
- [ ] Domain join successful ✓

### Step 4: Verify Group Membership
- [ ] Run (from management machine): `Get-ADPrincipalGroupMembership -Identity XXSUPDEP01`
- [ ] Membership verified ✓
- [ ] In security group: `ROLE-GPO_CENTRAL-SERVER` ✓

### Step 5: Verify OU Placement
- [ ] Run: `(Get-ADComputer XXSUPDEP01).DistinguishedName`
- [ ] OU: `OU=Deployment Servers,OU=Servers,OU=Resources,...` ✓

---

## PHASE 4: CONFIGURATION VERIFICATION (4:30 PM - 5:00 PM)

### Network & DNS
- [ ] Firewall disabled: `Get-NetFirewallProfile | Select Enabled`
- [ ] All profiles: **False** ✓
- [ ] DNS servers correct: `Get-DnsClient`
- [ ] DNS suffix set ✓
- [ ] Network connectivity: `Test-NetConnection -ComputerName 10.XX.1.10`
- [ ] OK ✓

### Services & Updates
- [ ] Windows Update disabled: `Get-Service wuauserv`
- [ ] Status: **Stopped** ✓
- [ ] Start Type: **Disabled** ✓
- [ ] No pending updates: `Get-HotFix | Sort InstalledOn -Descending | Select -First 5`
- [ ] Latest patches applied ✓

### Timezone & Time
- [ ] Check timezone: `Get-TimeZone`
- [ ] Timezone: `_____________________` ✓
- [ ] Time synchronized: `w32tm /query /status`
- [ ] Time correct ✓

### Active Directory
- [ ] Domain join verified ✓
- [ ] Local admin password working ✓
- [ ] Domain admin can access ✓
- [ ] Group policies applied: `gpupdate /force /sync`
- [ ] GPO update successful ✓

---

## PHASE 5: DFS REPLICATION (5:00 PM - 5:30 PM)

### Step 1: Configure DFS Replication
- [ ] Run (from new server or DFS server): `.\Configure-DFSReplication.ps1 -Territory "XX"`
- [ ] Script execution completed ✓
- [ ] Replication group created ✓
- [ ] Group name: `IT-Support-Data-Transfer` ✓

### Step 2: Verify DFS Configuration
- [ ] Replication group exists: `Get-DfsReplicationGroup`
- [ ] Confirmed ✓
- [ ] Members listed: `Get-DfsReplicationGroup | Get-DfsReplicationGroupMember`
- [ ] Member count: `_____________________` ✓
- [ ] Connections created: `Get-DfsReplicationGroup | Get-DfsReplicationGroupConnection`
- [ ] Connection count: `_____________________` ✓

### Step 3: Monitor Replication Status
- [ ] Check replication health: `Get-DfsReplicationGroupMembership | Get-DfsReplicationGroupMembershipHealth`
- [ ] Status review:
  - [ ] Server 1: `_____________________`
  - [ ] Server 2: `_____________________`
  - [ ] Server 3: `_____________________`
- [ ] Replication healthy ✓

**Note:** Initial replication may take time. Backlog should reduce over next 2-4 hours.

---

## PHASE 6: POST-MIGRATION TASKS (5:30 PM - 6:00 PM)

### Cleanup & Documentation
- [ ] Remove old server object from AD
- [ ] Confirmed deleted ✓
- [ ] Update Bitwarden - mark old creds as deprecated ✓
- [ ] Create new credential entry for XXSUPDEP01 ✓
- [ ] Archive logs: `logs/` directory backed up ✓
- [ ] Document any issues encountered ✓

### Icinga & Monitoring
- [ ] Remove downtime window from Icinga
- [ ] Check monitoring status
- [ ] Server monitoring active ✓
- [ ] All checks passing ✓

### Stakeholder Communication
- [ ] Send completion email
- [ ] To: `_____________________`
- [ ] Include: New IP, old IP terminated, next steps
- [ ] Team notification sent ✓
- [ ] Update change ticket as completed ✓

### Final Verification (1 Hour Post-Migration)
- [ ] Services running: `Get-Service | Where StartType -eq Automatic`
- [ ] All critical services running ✓
- [ ] Check event logs for errors: `Get-EventLog -LogName System -Newest 50`
- [ ] No critical errors ✓
- [ ] DFS backlog reducing: `Get-DfsReplicationGroupMembership | Get-DfsReplicationGroupMembershipHealth`
- [ ] Backlog: `_____________________` ✓

---

## ROLLBACK PROCEDURES (If Needed)

### If Failure Occurs Before Domain Join
1. [ ] Terminate new server: `./AWS-ServerMigration.sh --territory XX --action terminate`
2. [ ] Verify old server still accessible
3. [ ] Continue with old server
4. [ ] Document reason for failure
5. [ ] Schedule retry for next week

### If Failure Occurs After Domain Join
1. [ ] Shutdown new server
2. [ ] Restore old server from backup
3. [ ] Verify old server functionality
4. [ ] Restore DFS from backup: `Import-Clixml D:\DFS_Backup.xml`
5. [ ] Test client connections
6. [ ] Document root cause
7. [ ] Plan corrective actions

### If DFS Replication Fails
1. [ ] Check DFS service: `Get-Service DFSR`
2. [ ] Verify replication paths exist
3. [ ] Check firewall rules for ports 445, 5985
4. [ ] Review Event Viewer > DFS Replication logs
5. [ ] Restart DFS service if needed: `Restart-Service DFSR`
6. [ ] Force replication update if needed

---

## SIGN-OFF

### Migration Validation
- [ ] All phases completed successfully
- [ ] No critical errors encountered
- [ ] Server operational and responding
- [ ] DFS replication working
- [ ] Monitoring active
- [ ] Stakeholders notified

### Sign-Off By
**Migration Lead:** `_____________________` Date: `_____________________`

**Technical Lead:** `_____________________` Date: `_____________________`

**Approver:** `_____________________` Date: `_____________________`

---

## IMPORTANT CONTACTS

```
Infrastructure Team Lead: _____________________
AWS Account Manager:      _____________________
Active Directory Admin:   _____________________
DFS Replication Admin:    _____________________
Icinga Administrator:     _____________________
Change Management:        _____________________
```

---

## NOTES & ISSUES LOG

```
Time: _________ Issue: _________________________________
Resolution: ____________________________________________________

Time: _________ Issue: _________________________________
Resolution: ____________________________________________________

Time: _________ Issue: _________________________________
Resolution: ____________________________________________________
```

---

## QUICK REFERENCE

**Territory:** XX  
**Old Server:** XXSUPDEP01  
**New Server:** XXSUPDEP01 (10.XX.0.40)  
**Old Server:** XXSUPDEP01-OLD (terminated)  
**Domain:** company.local  
**Primary DNS:** 10.XX.1.10  
**Secondary DNS:** 10.XX.1.20  
**DFS Group:** IT-Support-Data-Transfer  
**OU Path:** OU=Deployment Servers,OU=Servers,OU=Resources,DC=...  

---

**Print & Complete During Migration**  
**Keep in secure location for audit trail**  
**Expected duration: 8 hours (8 AM - 6 PM)**
