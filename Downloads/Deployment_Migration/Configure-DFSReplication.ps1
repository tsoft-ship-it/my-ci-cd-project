# =============================================================================
# DFS REPLICATION CONFIGURATION SCRIPT
# Create and configure DFS replication groups and folders
# =============================================================================
# Usage: .\Configure-DFSReplication.ps1 -Territory "US" -ReplicationGroup "IT-Support-Data-Transfer"
# =============================================================================

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("US", "EU", "APAC", "CA", "AU")]
    [string]$Territory,
    
    [Parameter(Mandatory=$false)]
    [string]$ReplicationGroup = "IT-Support-Data-Transfer",
    
    [Parameter(Mandatory=$false)]
    [string[]]$ReplicationServers,
    
    [Parameter(Mandatory=$false)]
    [string]$ReplicationPath = "D:\ReplicationData",
    
    [Parameter(Mandatory=$false)]
    [switch]$RemoveOldGroup,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Require Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator" -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = "Continue"

# Territory Configuration
$TerritoryConfig = @{
    "US" = @{
        Domain = "company.local"
        DFSNamespace = "\\company.local\dfs\deployment"
        ReplicationServers = @("USSUPDEP01", "USSUPDEP02", "USSUPDEP03")
    }
    "EU" = @{
        Domain = "eu.company.local"
        DFSNamespace = "\\eu.company.local\dfs\deployment"
        ReplicationServers = @("EUSUPDEP01", "EUSUPDEP02", "EUSUPDEP03")
    }
    "APAC" = @{
        Domain = "apac.company.local"
        DFSNamespace = "\\apac.company.local\dfs\deployment"
        ReplicationServers = @("APSUPDEP01", "APSUPDEP02", "APSUPDEP03")
    }
    "CA" = @{
        Domain = "ca.company.local"
        DFSNamespace = "\\ca.company.local\dfs\deployment"
        ReplicationServers = @("CASUPDEP01", "CASUPDEP02", "CASUPDEP03")
    }
    "AU" = @{
        Domain = "au.company.local"
        DFSNamespace = "\\au.company.local\dfs\deployment"
        ReplicationServers = @("AUSUPDEP01", "AUSUPDEP02", "AUSUPDEP03")
    }
}

if (-not $TerritoryConfig.ContainsKey($Territory)) {
    Write-Host "ERROR: Invalid territory '$Territory'" -ForegroundColor Red
    exit 1
}

$Config = $TerritoryConfig[$Territory]

# Use default or provided servers
if (-not $ReplicationServers) {
    $ReplicationServers = $Config.ReplicationServers
}

$TranscriptPath = "C:\Logs\DFSConfiguration_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Create logs directory
if (-not (Test-Path "C:\Logs")) {
    New-Item -ItemType Directory -Path "C:\Logs" -Force | Out-Null
}

Start-Transcript -Path $TranscriptPath

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              DFS REPLICATION CONFIGURATION SCRIPT                             ║" -ForegroundColor Cyan
Write-Host "║   Territory: $Territory | Replication Group: $ReplicationGroup                 ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# 1. CHECK PREREQUISITES
# =============================================================================

Write-Host "Step 1: Checking Prerequisites..." -ForegroundColor Yellow

# Check for DFS Replication feature
try {
    $DFSFeature = Get-WindowsFeature -Name FS-DFS-Replication
    
    if ($DFSFeature.Installed -eq $false) {
        Write-Host "Installing DFS Replication feature..."
        Install-WindowsFeature -Name FS-DFS-Replication -IncludeManagementTools -Restart
        exit
    } else {
        Write-Host "✓ DFS Replication feature is installed" -ForegroundColor Green
    }
} catch {
    Write-Host "WARNING: Could not check DFS Replication feature: $_" -ForegroundColor Yellow
}

# Check for DFS Namespace feature
try {
    $DFSNamespace = Get-WindowsFeature -Name FS-DFS-Namespace
    
    if ($DFSNamespace.Installed -eq $false) {
        Write-Host "Installing DFS Namespace feature..."
        Install-WindowsFeature -Name FS-DFS-Namespace -IncludeManagementTools -Restart
        exit
    } else {
        Write-Host "✓ DFS Namespace feature is installed" -ForegroundColor Green
    }
} catch {
    Write-Host "WARNING: Could not check DFS Namespace feature: $_" -ForegroundColor Yellow
}

# Verify replication path exists
Write-Host ""
Write-Host "Verifying replication path: $ReplicationPath"

if (-not (Test-Path $ReplicationPath)) {
    Write-Host "Creating replication path: $ReplicationPath"
    try {
        New-Item -ItemType Directory -Path $ReplicationPath -Force | Out-Null
        Write-Host "✓ Replication path created" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to create replication path: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✓ Replication path exists" -ForegroundColor Green
}

# =============================================================================
# 2. REMOVE OLD REPLICATION GROUP (if requested)
# =============================================================================

if ($RemoveOldGroup) {
    Write-Host ""
    Write-Host "Step 2: Removing Old Replication Group..." -ForegroundColor Yellow
    
    try {
        $ExistingGroup = Get-DfsReplicationGroup -GroupName $ReplicationGroup -ErrorAction SilentlyContinue
        
        if ($ExistingGroup) {
            Write-Host "Found existing replication group: $ReplicationGroup"
            Write-Host "This will delete all replication configuration and replicated folders"
            
            if ($Force) {
                Write-Host "Removing group (Force mode)..."
            } else {
                $Confirmation = Read-Host "Confirm deletion? (yes/no)"
                if ($Confirmation -ne "yes") {
                    Write-Host "Deletion cancelled"
                    exit
                }
            }
            
            Remove-DfsReplicationGroup -GroupName $ReplicationGroup -RemoveReplicatedFolders -Force
            Write-Host "✓ Old replication group removed" -ForegroundColor Green
            
            # Wait for deletion to propagate
            Start-Sleep -Seconds 5
        } else {
            Write-Host "! Replication group '$ReplicationGroup' not found" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "ERROR: Failed to remove replication group: $_" -ForegroundColor Red
    }
}

# =============================================================================
# 3. CREATE REPLICATION GROUP
# =============================================================================

Write-Host ""
Write-Host "Step 3: Creating Replication Group..." -ForegroundColor Yellow

try {
    $ExistingGroup = Get-DfsReplicationGroup -GroupName $ReplicationGroup -ErrorAction SilentlyContinue
    
    if ($ExistingGroup) {
        Write-Host "✓ Replication group already exists: $ReplicationGroup" -ForegroundColor Green
    } else {
        Write-Host "Creating new replication group: $ReplicationGroup"
        
        New-DfsReplicationGroup -GroupName $ReplicationGroup `
            -Description "Deployment server data synchronization for Territory: $Territory" `
            -ErrorAction Stop
        
        Write-Host "✓ Replication group created successfully" -ForegroundColor Green
    }
} catch {
    Write-Host "ERROR: Failed to create replication group: $_" -ForegroundColor Red
    exit 1
}

# =============================================================================
# 4. ADD REPLICATION GROUP MEMBERS
# =============================================================================

Write-Host ""
Write-Host "Step 4: Adding Members to Replication Group..." -ForegroundColor Yellow

try {
    $Group = Get-DfsReplicationGroup -GroupName $ReplicationGroup
    $ExistingMembers = $Group | Get-DfsReplicationGroupMember
    
    foreach ($Server in $ReplicationServers) {
        try {
            # Check if server already is a member
            $IsMember = $ExistingMembers | Where-Object { $_.ComputerName -eq $Server }
            
            if ($IsMember) {
                Write-Host "✓ $Server is already a member" -ForegroundColor Green
            } else {
                Write-Host "Adding $Server to replication group..."
                
                # Test connectivity
                if (Test-Connection -ComputerName $Server -Count 1 -ErrorAction SilentlyContinue) {
                    Add-DfsReplicationGroupMember -GroupName $ReplicationGroup `
                        -ComputerName $Server `
                        -ErrorAction Stop
                    
                    Write-Host "✓ $Server added to replication group" -ForegroundColor Green
                } else {
                    Write-Host "! $Server is not reachable" -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Host "ERROR: Failed to add $Server`: $_" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "ERROR: Failed to add group members: $_" -ForegroundColor Red
}

# =============================================================================
# 5. CREATE REPLICATED FOLDER
# =============================================================================

Write-Host ""
Write-Host "Step 5: Creating Replicated Folder..." -ForegroundColor Yellow

$FolderName = "IT-Support-Data"

try {
    $Group = Get-DfsReplicationGroup -GroupName $ReplicationGroup
    $ExistingFolder = $Group | Get-DfsReplicatedFolder -ErrorAction SilentlyContinue
    
    if ($ExistingFolder | Where-Object { $_.FolderName -eq $FolderName }) {
        Write-Host "✓ Replicated folder already exists: $FolderName" -ForegroundColor Green
    } else {
        Write-Host "Creating replicated folder: $FolderName"
        
        New-DfsReplicatedFolder -GroupName $ReplicationGroup `
            -FolderName $FolderName `
            -Description "Shared deployment data and resources" `
            -ErrorAction Stop
        
        Write-Host "✓ Replicated folder created" -ForegroundColor Green
    }
} catch {
    Write-Host "ERROR: Failed to create replicated folder: $_" -ForegroundColor Red
}

# =============================================================================
# 6. ADD FOLDER MEMBERS
# =============================================================================

Write-Host ""
Write-Host "Step 6: Adding Members to Replicated Folder..." -ForegroundColor Yellow

try {
    $Group = Get-DfsReplicationGroup -GroupName $ReplicationGroup
    $Folder = $Group | Get-DfsReplicatedFolder -FolderName $FolderName
    $ExistingMembers = $Folder | Get-DfsReplicationGroupMembership
    
    foreach ($Server in $ReplicationServers) {
        try {
            $IsMember = $ExistingMembers | Where-Object { $_.ComputerName -eq $Server }
            
            if ($IsMember) {
                Write-Host "✓ $Server is already a member of replicated folder" -ForegroundColor Green
            } else {
                Write-Host "Adding $Server to replicated folder..."
                
                Add-DfsReplicationGroupMembership -GroupName $ReplicationGroup `
                    -FolderName $FolderName `
                    -ComputerName $Server `
                    -ContentPath $ReplicationPath `
                    -ErrorAction Stop
                
                Write-Host "✓ $Server added to replicated folder (Content path: $ReplicationPath)" -ForegroundColor Green
            }
        } catch {
            Write-Host "ERROR: Failed to add $Server to folder: $_" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "ERROR: Failed to add folder members: $_" -ForegroundColor Red
}

# =============================================================================
# 7. CREATE CONNECTIONS BETWEEN MEMBERS
# =============================================================================

Write-Host ""
Write-Host "Step 7: Creating Replication Connections..." -ForegroundColor Yellow

try {
    $Group = Get-DfsReplicationGroup -GroupName $ReplicationGroup
    $ExistingConnections = $Group | Get-DfsReplicationGroupConnection
    
    $ServerCount = $ReplicationServers.Count
    
    for ($i = 0; $i -lt $ServerCount; $i++) {
        for ($j = $i + 1; $j -lt $ServerCount; $j++) {
            $SourceServer = $ReplicationServers[$i]
            $DestServer = $ReplicationServers[$j]
            
            try {
                # Check if connection already exists
                $Exists = $ExistingConnections | Where-Object {
                    ($_.SourceComputerName -eq $SourceServer -and $_.DestinationComputerName -eq $DestServer) -or
                    ($_.SourceComputerName -eq $DestServer -and $_.DestinationComputerName -eq $SourceServer)
                }
                
                if ($Exists) {
                    Write-Host "✓ Connection already exists: $SourceServer <-> $DestServer" -ForegroundColor Green
                } else {
                    Write-Host "Creating connection: $SourceServer -> $DestServer"
                    
                    New-DfsReplicationGroupConnection -GroupName $ReplicationGroup `
                        -SourceComputerName $SourceServer `
                        -DestinationComputerName $DestServer `
                        -ErrorAction Stop
                    
                    Write-Host "✓ Connection created: $SourceServer -> $DestServer" -ForegroundColor Green
                }
            } catch {
                Write-Host "ERROR: Failed to create connection: $_" -ForegroundColor Red
            }
        }
    }
} catch {
    Write-Host "ERROR: Failed to create replication connections: $_" -ForegroundColor Red
}

# =============================================================================
# 8. VERIFY CONFIGURATION
# =============================================================================

Write-Host ""
Write-Host "Step 8: Verifying DFS Replication Configuration..." -ForegroundColor Yellow

try {
    $Group = Get-DfsReplicationGroup -GroupName $ReplicationGroup
    
    Write-Host ""
    Write-Host "Replication Group: $($Group.GroupName)" -ForegroundColor White
    Write-Host "Description: $($Group.Description)"
    Write-Host ""
    
    $Members = $Group | Get-DfsReplicationGroupMember
    Write-Host "Members ($($Members.Count)):" -ForegroundColor White
    foreach ($Member in $Members) {
        Write-Host "  ✓ $($Member.ComputerName) - $($Member.State)" -ForegroundColor Green
    }
    
    Write-Host ""
    $Folders = $Group | Get-DfsReplicatedFolder
    Write-Host "Replicated Folders ($($Folders.Count)):" -ForegroundColor White
    foreach ($Folder in $Folders) {
        Write-Host "  ✓ $($Folder.FolderName)" -ForegroundColor Green
    }
    
    Write-Host ""
    $Connections = $Group | Get-DfsReplicationGroupConnection
    Write-Host "Replication Connections ($($Connections.Count)):" -ForegroundColor White
    foreach ($Connection in $Connections) {
        Write-Host "  ✓ $($Connection.SourceComputerName) -> $($Connection.DestinationComputerName) [$($Connection.State)]" -ForegroundColor Green
    }
} catch {
    Write-Host "ERROR: Failed to verify configuration: $_" -ForegroundColor Red
}

# =============================================================================
# 9. CHECK REPLICATION STATUS
# =============================================================================

Write-Host ""
Write-Host "Step 9: Checking Replication Status..." -ForegroundColor Yellow

try {
    Write-Host "Getting replication backlog..."
    
    $BacklogStatistics = Get-DfsReplicationGroupMembership -GroupName $ReplicationGroup -FolderName $FolderName | 
        Get-DfsReplicationGroupMembershipHealth
    
    foreach ($Stat in $BacklogStatistics) {
        Write-Host ""
        Write-Host "Member: $($Stat.ComputerName)" -ForegroundColor White
        Write-Host "  State: $($Stat.MembershipState)"
        Write-Host "  Health: $($Stat.Health)"
        Write-Host "  Update Time: $($Stat.LastUpdateTime)"
    }
} catch {
    Write-Host "WARNING: Could not retrieve replication status: $_" -ForegroundColor Yellow
    Write-Host "Status may take time to appear. Check again in a few minutes."
}

# =============================================================================
# 10. SUMMARY & NEXT STEPS
# =============================================================================

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                  DFS CONFIGURATION COMPLETE                                   ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  Territory: $Territory"
Write-Host "  Replication Group: $ReplicationGroup"
Write-Host "  Replicated Folder: $FolderName"
Write-Host "  Content Path: $ReplicationPath"
Write-Host "  Members: $($ReplicationServers -join ', ')"
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Monitor replication status using:"
Write-Host "   Get-DfsReplicationGroupMembership -GroupName '$ReplicationGroup' -FolderName '$FolderName' | Get-DfsReplicationGroupMembershipHealth"
Write-Host ""
Write-Host "2. Check DFS health in Event Viewer > Applications and Services Logs > DFS Replication"
Write-Host ""
Write-Host "3. Use DFS Management MMC snap-in for detailed monitoring"
Write-Host ""
Write-Host "4. Initial replication may take time depending on data size"
Write-Host ""

Write-Host "Transcript saved to: $TranscriptPath"
Write-Host ""

Stop-Transcript
