<#
.SYNOPSIS
    Configures API permissions and custom scopes for Tour Bus Leasing application
    
.DESCRIPTION
    This script configures Microsoft Graph API permissions and creates custom OAuth2 scopes
    for the Tour Bus Leasing application to enable fine-grained access control.
    
.PARAMETER ApplicationId
    The Application ID of the registered app
    
.PARAMETER TenantId
    The Azure AD Tenant ID
    
.PARAMETER Environment
    The environment (dev, qa, or prod)
    
.PARAMETER GrantAdminConsent
    Automatically grant admin consent for permissions
    
.EXAMPLE
    .\Configure-ApiScopes.ps1 -ApplicationId "app-id" -TenantId "tenant-id" -Environment dev -GrantAdminConsent
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApplicationId,
    
    [Parameter(Mandatory = $true)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'qa', 'prod')]
    [string]$Environment,
    
    [switch]$GrantAdminConsent
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

Write-Log "========================================" -Level Info
Write-Log "Configuring API Permissions and Scopes" -Level Info
Write-Log "========================================" -Level Info
Write-Log "Application ID: $ApplicationId" -Level Info
Write-Log "Tenant ID: $TenantId" -Level Info
Write-Log "Environment: $Environment" -Level Info

# Verify Azure CLI is logged in
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Log "Please login to Azure CLI first: az login" -Level Error
    exit 1
}

Write-Log "Connected to Azure tenant: $($account.tenantId)" -Level Success

# Get the application
Write-Log "Getting application details..." -Level Info
$app = az ad app show --id $ApplicationId 2>$null | ConvertFrom-Json

if (-not $app) {
    Write-Log "Application not found: $ApplicationId" -Level Error
    exit 1
}

Write-Log "Found application: $($app.displayName)" -Level Success

# Define custom OAuth2 permission scopes
Write-Log "Configuring custom API scopes..." -Level Info

$oauth2Permissions = @(
    @{
        adminConsentDescription = "Allows the app to read bus leasing data on behalf of the signed-in user"
        adminConsentDisplayName = "Read bus leasing data"
        id = [guid]::NewGuid().ToString()
        isEnabled = $true
        type = "User"
        userConsentDescription = "Allow the app to read bus leasing data on your behalf"
        userConsentDisplayName = "Read your bus leasing data"
        value = "BusLeasing.Read"
    },
    @{
        adminConsentDescription = "Allows the app to create and update bus leasing data on behalf of the signed-in user"
        adminConsentDisplayName = "Write bus leasing data"
        id = [guid]::NewGuid().ToString()
        isEnabled = $true
        type = "User"
        userConsentDescription = "Allow the app to create and update bus leasing data on your behalf"
        userConsentDisplayName = "Create and update your bus leasing data"
        value = "BusLeasing.Write"
    },
    @{
        adminConsentDescription = "Allows the app to perform administrative functions on bus leasing data on behalf of the signed-in user"
        adminConsentDisplayName = "Administer bus leasing data"
        id = [guid]::NewGuid().ToString()
        isEnabled = $true
        type = "Admin"
        userConsentDescription = "Allow the app to perform administrative functions on bus leasing data on your behalf"
        userConsentDisplayName = "Administer bus leasing data"
        value = "BusLeasing.Admin"
    }
)

# Update the application with custom scopes
$scopesJson = $oauth2Permissions | ConvertTo-Json -Depth 10
$scopesFile = "oauth2-permissions-temp.json"
$scopesJson | Out-File -FilePath $scopesFile -Encoding UTF8

try {
    # First, we need to disable any existing oauth2Permissions
    Write-Log "Updating OAuth2 permission scopes..." -Level Info
    
    # Get existing permissions and disable them
    $existingPermissions = $app.api.oauth2PermissionScopes
    if ($existingPermissions) {
        $disabledPermissions = $existingPermissions | ForEach-Object {
            $_ | Add-Member -MemberType NoteProperty -Name "isEnabled" -Value $false -Force
            $_
        }
        $disabledJson = $disabledPermissions | ConvertTo-Json -Depth 10
        $disabledJson | Out-File -FilePath "disabled-temp.json" -Encoding UTF8
        
        az ad app update --id $ApplicationId --set api.oauth2PermissionScopes=@disabled-temp.json 2>$null
        Remove-Item "disabled-temp.json" -Force
        
        Start-Sleep -Seconds 2
    }
    
    # Now add the new permissions
    az ad app update --id $ApplicationId --set api.oauth2PermissionScopes=@$scopesFile
    Write-Log "Custom OAuth2 scopes configured successfully" -Level Success
}
catch {
    Write-Log "Failed to configure OAuth2 scopes: $_" -Level Error
}
finally {
    Remove-Item $scopesFile -Force -ErrorAction SilentlyContinue
}

# Configure preAuthorizedApplications if needed
Write-Log "Configuring pre-authorized applications..." -Level Info

$preAuthorizedApps = @(
    @{
        appId = $ApplicationId  # Self-authorize for testing
        delegatedPermissionIds = $oauth2Permissions | ForEach-Object { $_.id }
    }
)

$preAuthJson = @{
    preAuthorizedApplications = $preAuthorizedApps
} | ConvertTo-Json -Depth 10

$preAuthFile = "preauth-temp.json"
$preAuthJson | Out-File -FilePath $preAuthFile -Encoding UTF8

try {
    az ad app update --id $ApplicationId --set api=@$preAuthFile
    Write-Log "Pre-authorized applications configured" -Level Success
}
catch {
    Write-Log "Could not configure pre-authorized applications: $_" -Level Warning
}
finally {
    Remove-Item $preAuthFile -Force -ErrorAction SilentlyContinue
}

# Verify Microsoft Graph permissions are configured
Write-Log "Verifying Microsoft Graph permissions..." -Level Info

$requiredGraphPermissions = @(
    @{ id = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; type = "Scope"; name = "User.Read" }
    @{ id = "98830695-27a2-44f7-8c18-0c3ebc9698f6"; type = "Scope"; name = "GroupMember.Read.All" }
    @{ id = "37f7f235-527c-4136-accd-4a02d197296e"; type = "Scope"; name = "openid" }
    @{ id = "14dad69e-099b-42c9-810b-d002981feec1"; type = "Scope"; name = "profile" }
    @{ id = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0"; type = "Scope"; name = "email" }
)

$currentPermissions = $app.requiredResourceAccess | Where-Object { $_.resourceAppId -eq "00000003-0000-0000-c000-000000000000" }

if (-not $currentPermissions) {
    Write-Log "Microsoft Graph permissions not found. Adding them..." -Level Warning
    
    $graphPermissions = @{
        resourceAppId = "00000003-0000-0000-c000-000000000000"
        resourceAccess = $requiredGraphPermissions | ForEach-Object {
            @{
                id = $_.id
                type = $_.type
            }
        }
    }
    
    $permissionsArray = @($graphPermissions)
    $permissionsJson = $permissionsArray | ConvertTo-Json -Depth 10
    $permissionsFile = "graph-permissions-temp.json"
    $permissionsJson | Out-File -FilePath $permissionsFile -Encoding UTF8
    
    az ad app update --id $ApplicationId --set requiredResourceAccess=@$permissionsFile
    Remove-Item $permissionsFile -Force
    
    Write-Log "Microsoft Graph permissions added" -Level Success
} else {
    Write-Log "Microsoft Graph permissions already configured" -Level Success
}

# Grant admin consent if requested
if ($GrantAdminConsent) {
    Write-Log "Granting admin consent for API permissions..." -Level Info
    
    try {
        # Get service principal ID
        $sp = az ad sp list --filter "appId eq '$ApplicationId'" --query "[0]" | ConvertFrom-Json
        
        if ($sp) {
            # Grant consent for Microsoft Graph
            az ad app permission admin-consent --id $ApplicationId
            Write-Log "Admin consent granted successfully" -Level Success
        } else {
            Write-Log "Service principal not found. Please create it first." -Level Warning
        }
    }
    catch {
        Write-Log "Could not grant admin consent automatically. Please do this manually in Azure Portal." -Level Warning
    }
}

# Generate documentation
Write-Log "`nGenerating API permissions documentation..." -Level Info

$documentation = @"
# API Permissions and Scopes Configuration
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Environment: $Environment
Application ID: $ApplicationId

## Microsoft Graph Permissions (Delegated)
| Permission | ID | Justification |
|------------|-----|---------------|
| User.Read | e1fe6dd8-ba31-4d61-89e7-88639da4683d | Read user profile for personalization |
| GroupMember.Read.All | 98830695-27a2-44f7-8c18-0c3ebc9698f6 | Determine user's security group memberships for RBAC |
| openid | 37f7f235-527c-4136-accd-4a02d197296e | Enable OpenID Connect authentication flow |
| profile | 14dad69e-099b-42c9-810b-d002981feec1 | Access user's basic profile information |
| email | 64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0 | Access user's email for notifications |

## Custom OAuth2 Scopes
| Scope | Type | Description |
|-------|------|-------------|
| BusLeasing.Read | User | Read access to bus leasing data |
| BusLeasing.Write | User | Write access to bus leasing data |
| BusLeasing.Admin | Admin | Administrative access to all bus leasing functions |

## Usage Examples

### Frontend (MSAL.js)
\`\`\`javascript
const loginRequest = {
    scopes: [
        "openid",
        "profile", 
        "User.Read",
        "GroupMember.Read.All",
        "api://$ApplicationId/BusLeasing.Read",
        "api://$ApplicationId/BusLeasing.Write"
    ]
};
\`\`\`

### Backend (Token Validation)
\`\`\`javascript
// Validate scope in JWT token
const requiredScope = 'BusLeasing.Write';
if (!token.scp.includes(requiredScope)) {
    return res.status(403).json({ error: 'Insufficient scope' });
}
\`\`\`

## Next Steps
1. Grant admin consent in Azure Portal if not done automatically
2. Update application code to request appropriate scopes
3. Implement scope-based authorization in API endpoints
4. Test with different user accounts and permission levels
"@

$docFile = "api-permissions-$Environment.md"
$documentation | Out-File -FilePath $docFile -Encoding UTF8
Write-Log "Documentation saved to: $docFile" -Level Success

# Generate test configuration
Write-Log "`nGenerating test configuration..." -Level Info

$testConfig = @{
    ApplicationId = $ApplicationId
    TenantId = $TenantId
    Environment = $Environment
    GraphPermissions = $requiredGraphPermissions | ForEach-Object { $_.name }
    CustomScopes = $oauth2Permissions | ForEach-Object { $_.value }
    ScopeEndpoint = "api://$ApplicationId"
    ConfiguredDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
}

$testConfigFile = "api-scopes-config-$Environment.json"
$testConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $testConfigFile -Encoding UTF8
Write-Log "Test configuration saved to: $testConfigFile" -Level Success

Write-Log "`n========================================" -Level Info
Write-Log "API Permissions Configuration Complete!" -Level Success
Write-Log "========================================" -Level Info
Write-Log "Custom Scopes:" -Level Info
foreach ($scope in $oauth2Permissions) {
    Write-Log "  - $($scope.value): $($scope.adminConsentDisplayName)" -Level Info
}
Write-Log "`nIMPORTANT: Remember to grant admin consent in Azure Portal!" -Level Warning