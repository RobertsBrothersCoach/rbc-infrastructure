<#
.SYNOPSIS
    Configures Azure AD security groups and role assignments for Tour Bus Leasing
    
.DESCRIPTION
    Creates security groups, assigns users, and configures app role assignments
    
.PARAMETER Environment
    The environment to configure (dev, qa, or prod)
    
.PARAMETER ApplicationId
    The Application ID of the registered app
    
.PARAMETER ImportUsersFromCsv
    Path to CSV file containing user assignments
    
.EXAMPLE
    .\Configure-SecurityGroups.ps1 -Environment dev -ApplicationId "app-id"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'qa', 'prod')]
    [string]$Environment,
    
    [Parameter(Mandatory = $true)]
    [string]$ApplicationId,
    
    [string]$ImportUsersFromCsv,
    
    [switch]$AssignAppRoles
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Security group definitions with role mappings
$securityGroups = @(
    @{
        Name = "BusLeasing-Administrators-$Environment"
        Description = "Full system access and administrative privileges for $Environment"
        MailNickname = "BusLeasingAdmins$Environment"
        AppRole = "Administrator"
        DefaultMembers = @()  # Add admin emails here
    }
    @{
        Name = "BusLeasing-Managers-$Environment"
        Description = "Management level access to all modules in $Environment"
        MailNickname = "BusLeasingManagers$Environment"
        AppRole = "Manager"
        DefaultMembers = @()
    }
    @{
        Name = "BusLeasing-CRM-Users-$Environment"
        Description = "Access to CRM module for client management in $Environment"
        MailNickname = "BusLeasingCRM$Environment"
        AppRole = "CRMUser"
        DefaultMembers = @()
    }
    @{
        Name = "BusLeasing-Fleet-Managers-$Environment"
        Description = "Access to fleet management and maintenance modules in $Environment"
        MailNickname = "BusLeasingFleet$Environment"
        AppRole = "FleetManager"
        DefaultMembers = @()
    }
    @{
        Name = "BusLeasing-Finance-Users-$Environment"
        Description = "Access to financial and reporting modules in $Environment"
        MailNickname = "BusLeasingFinance$Environment"
        AppRole = "FinanceUser"
        DefaultMembers = @()
    }
    @{
        Name = "BusLeasing-ReadOnly-Users-$Environment"
        Description = "Read-only access to all modules in $Environment"
        MailNickname = "BusLeasingReadOnly$Environment"
        AppRole = "ReadOnlyUser"
        DefaultMembers = @()
    }
)

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        'Error' { Write-Host $logMessage -ForegroundColor Red }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage }
    }
}

# Main execution
Write-Log "========================================" -Level Info
Write-Log "Configuring Security Groups for $Environment" -Level Info
Write-Log "========================================" -Level Info

# Verify Azure connection
$context = Get-AzContext
if (-not $context) {
    Write-Log "Please connect to Azure using Connect-AzAccount" -Level Error
    exit 1
}

Write-Log "Connected to Azure tenant: $($context.Tenant.Id)" -Level Success

# Get the service principal for the app
Write-Log "Getting service principal for application..." -Level Info
$servicePrincipal = az ad sp list --filter "appId eq '$ApplicationId'" --query "[0]" | ConvertFrom-Json

if (-not $servicePrincipal) {
    Write-Log "Service principal not found for Application ID: $ApplicationId" -Level Error
    exit 1
}

Write-Log "Found service principal: $($servicePrincipal.displayName)" -Level Success

# Import users from CSV if provided
$userAssignments = @{}
if ($ImportUsersFromCsv -and (Test-Path $ImportUsersFromCsv)) {
    Write-Log "Importing user assignments from CSV..." -Level Info
    $csvData = Import-Csv $ImportUsersFromCsv
    
    foreach ($row in $csvData) {
        if (-not $userAssignments[$row.GroupName]) {
            $userAssignments[$row.GroupName] = @()
        }
        $userAssignments[$row.GroupName] += $row.UserPrincipalName
    }
    Write-Log "Imported $($csvData.Count) user assignments" -Level Success
}

# Create or update security groups
$createdGroups = @()
foreach ($group in $securityGroups) {
    Write-Log "Processing group: $($group.Name)" -Level Info
    
    # Check if group exists
    $existingGroup = az ad group list --display-name $group.Name --query "[0]" | ConvertFrom-Json
    
    if ($existingGroup) {
        Write-Log "  Group already exists with ID: $($existingGroup.id)" -Level Info
        $groupId = $existingGroup.id
    } else {
        # Create the group
        Write-Log "  Creating new group..." -Level Info
        $newGroup = az ad group create `
            --display-name $group.Name `
            --mail-nickname $group.MailNickname `
            --description $group.Description `
            --query "{id:id, displayName:displayName}" | ConvertFrom-Json
            
        $groupId = $newGroup.id
        Write-Log "  Group created with ID: $groupId" -Level Success
    }
    
    # Add members to group
    $members = if ($userAssignments[$group.Name]) {
        $userAssignments[$group.Name]
    } else {
        $group.DefaultMembers
    }
    
    if ($members.Count -gt 0) {
        Write-Log "  Adding $($members.Count) members to group..." -Level Info
        
        foreach ($member in $members) {
            try {
                # Get user ID
                $user = az ad user list --filter "userPrincipalName eq '$member'" --query "[0]" | ConvertFrom-Json
                
                if ($user) {
                    az ad group member add --group $groupId --member-id $user.id 2>$null
                    Write-Log "    Added: $member" -Level Success
                } else {
                    Write-Log "    User not found: $member" -Level Warning
                }
            } catch {
                Write-Log "    Failed to add $member : $_" -Level Warning
            }
        }
    }
    
    # Assign app role if requested
    if ($AssignAppRoles) {
        Write-Log "  Assigning app role: $($group.AppRole)" -Level Info
        
        try {
            # Get the app role ID
            $appRoles = az ad sp show --id $servicePrincipal.id --query "appRoles[?value=='$($group.AppRole)']" | ConvertFrom-Json
            
            if ($appRoles -and $appRoles.Count -gt 0) {
                $appRoleId = $appRoles[0].id
                
                # Create app role assignment
                $assignment = @{
                    principalId = $groupId
                    resourceId = $servicePrincipal.id
                    appRoleId = $appRoleId
                } | ConvertTo-Json -Compress
                
                az rest --method POST `
                    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($servicePrincipal.id)/appRoleAssignedTo" `
                    --headers "Content-Type=application/json" `
                    --body $assignment 2>$null
                    
                Write-Log "    App role assigned successfully" -Level Success
            } else {
                Write-Log "    App role not found: $($group.AppRole)" -Level Warning
            }
        } catch {
            # Assignment might already exist
            Write-Log "    App role assignment may already exist" -Level Info
        }
    }
    
    $createdGroups += @{
        GroupId = $groupId
        GroupName = $group.Name
        AppRole = $group.AppRole
        MemberCount = $members.Count
    }
}

# Generate summary report
Write-Log "`n========================================" -Level Info
Write-Log "Security Groups Configuration Summary" -Level Success
Write-Log "========================================" -Level Info
Write-Log "Environment: $Environment" -Level Info
Write-Log "Application ID: $ApplicationId" -Level Info
Write-Log "Groups Created/Updated: $($createdGroups.Count)" -Level Info

foreach ($group in $createdGroups) {
    Write-Log "  - $($group.GroupName)" -Level Info
    Write-Log "    Role: $($group.AppRole)" -Level Info
    Write-Log "    Members: $($group.MemberCount)" -Level Info
}

# Export configuration
$exportData = @{
    Environment = $Environment
    ApplicationId = $ApplicationId
    ServicePrincipalId = $servicePrincipal.id
    Groups = $createdGroups
    ConfiguredDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
}

$exportFile = "security-groups-config-$Environment.json"
$exportData | ConvertTo-Json -Depth 10 | Out-File $exportFile
Write-Log "`nConfiguration exported to: $exportFile" -Level Success

# Create sample CSV template if it doesn't exist
$sampleCsvFile = "user-assignments-template.csv"
if (-not (Test-Path $sampleCsvFile)) {
    $sampleData = @"
GroupName,UserPrincipalName,DisplayName,Role
BusLeasing-Administrators-$Environment,admin@company.com,Admin User,Administrator
BusLeasing-Managers-$Environment,manager@company.com,Manager User,Manager
BusLeasing-CRM-Users-$Environment,crm@company.com,CRM User,CRMUser
BusLeasing-Fleet-Managers-$Environment,fleet@company.com,Fleet Manager,FleetManager
BusLeasing-Finance-Users-$Environment,finance@company.com,Finance User,FinanceUser
BusLeasing-ReadOnly-Users-$Environment,readonly@company.com,Read Only User,ReadOnlyUser
"@
    $sampleData | Out-File $sampleCsvFile
    Write-Log "Sample CSV template created: $sampleCsvFile" -Level Info
}

Write-Log "`nSecurity groups configuration completed!" -Level Success