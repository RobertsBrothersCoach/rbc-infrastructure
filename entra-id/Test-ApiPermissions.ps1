<#
.SYNOPSIS
    Tests API permissions and scopes configuration for Tour Bus Leasing application
    
.DESCRIPTION
    Validates that all required Microsoft Graph permissions and custom scopes are properly configured
    
.PARAMETER ApplicationId
    The Application ID of the registered app
    
.PARAMETER TenantId
    The Azure AD Tenant ID
    
.PARAMETER TestUserEmail
    Email of a test user to validate permissions (optional)
    
.EXAMPLE
    .\Test-ApiPermissions.ps1 -ApplicationId "app-id" -TenantId "tenant-id"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApplicationId,
    
    [Parameter(Mandatory = $true)]
    [string]$TenantId,
    
    [string]$TestUserEmail
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-TestResult {
    param(
        [string]$Test,
        [ValidateSet('Pass', 'Fail', 'Warning', 'Info')]
        [string]$Result,
        [string]$Details = ""
    )
    
    $symbol = switch ($Result) {
        'Pass' { "✓"; $color = "Green" }
        'Fail' { "✗"; $color = "Red" }
        'Warning' { "⚠"; $color = "Yellow" }
        'Info' { "ℹ"; $color = "Cyan" }
    }
    
    $message = "$symbol $Test"
    if ($Details) {
        $message += " - $Details"
    }
    
    Write-Host $message -ForegroundColor $color
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "API Permissions and Scopes Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Application ID: $ApplicationId"
Write-Host "Tenant ID: $TenantId"
Write-Host ""

# Verify Azure CLI is logged in
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-TestResult "Azure CLI Authentication" "Fail" "Please run 'az login' first"
    exit 1
}
Write-TestResult "Azure CLI Authentication" "Pass" "Connected to tenant: $($account.tenantId)"

# Get application details
Write-Host "`nChecking Application Configuration..." -ForegroundColor Yellow
$app = az ad app show --id $ApplicationId 2>$null | ConvertFrom-Json

if (-not $app) {
    Write-TestResult "Application Exists" "Fail" "Application not found"
    exit 1
}
Write-TestResult "Application Exists" "Pass" $app.displayName

# Check Microsoft Graph Permissions
Write-Host "`nMicrosoft Graph Permissions:" -ForegroundColor Yellow
$requiredPermissions = @{
    "e1fe6dd8-ba31-4d61-89e7-88639da4683d" = "User.Read"
    "98830695-27a2-44f7-8c18-0c3ebc9698f6" = "GroupMember.Read.All"
    "37f7f235-527c-4136-accd-4a02d197296e" = "openid"
    "14dad69e-099b-42c9-810b-d002981feec1" = "profile"
    "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0" = "email"
}

$graphPermissions = $app.requiredResourceAccess | Where-Object { $_.resourceAppId -eq "00000003-0000-0000-c000-000000000000" }

if ($graphPermissions) {
    $configuredPermissions = $graphPermissions.resourceAccess | ForEach-Object { $_.id }
    
    foreach ($permId in $requiredPermissions.Keys) {
        if ($configuredPermissions -contains $permId) {
            Write-TestResult "  $($requiredPermissions[$permId])" "Pass"
        } else {
            Write-TestResult "  $($requiredPermissions[$permId])" "Fail" "Not configured"
        }
    }
} else {
    Write-TestResult "  Microsoft Graph Permissions" "Fail" "No Graph permissions configured"
}

# Check Custom OAuth2 Scopes
Write-Host "`nCustom OAuth2 Scopes:" -ForegroundColor Yellow
$requiredScopes = @("BusLeasing.Read", "BusLeasing.Write", "BusLeasing.Admin")

if ($app.api -and $app.api.oauth2PermissionScopes) {
    $configuredScopes = $app.api.oauth2PermissionScopes | ForEach-Object { $_.value }
    
    foreach ($scope in $requiredScopes) {
        if ($configuredScopes -contains $scope) {
            $scopeDetails = $app.api.oauth2PermissionScopes | Where-Object { $_.value -eq $scope }
            Write-TestResult "  $scope" "Pass" "Enabled: $($scopeDetails.isEnabled)"
        } else {
            Write-TestResult "  $scope" "Fail" "Not configured"
        }
    }
} else {
    Write-TestResult "  Custom Scopes" "Fail" "No custom scopes configured"
}

# Check Admin Consent Status
Write-Host "`nAdmin Consent Status:" -ForegroundColor Yellow
$sp = az ad sp list --filter "appId eq '$ApplicationId'" --query "[0]" | ConvertFrom-Json

if ($sp) {
    # Check if admin consent has been granted
    $graphApiId = "00000003-0000-0000-c000-000000000000"
    $grants = az ad sp show --id $sp.id --query "oauth2PermissionGrants" 2>$null | ConvertFrom-Json
    
    if ($grants) {
        Write-TestResult "  Admin Consent" "Pass" "Consent granted"
    } else {
        Write-TestResult "  Admin Consent" "Warning" "May require admin consent"
    }
} else {
    Write-TestResult "  Service Principal" "Fail" "Not created"
}

# Check Identifier URI
Write-Host "`nIdentifier URI:" -ForegroundColor Yellow
$expectedUri = "api://$ApplicationId"
$alternateUri = "api://tourbus-"

if ($app.identifierUris) {
    $uri = $app.identifierUris[0]
    if ($uri -eq $expectedUri -or $uri -like "$alternateUri*") {
        Write-TestResult "  Identifier URI" "Pass" $uri
    } else {
        Write-TestResult "  Identifier URI" "Warning" "Unexpected: $uri"
    }
} else {
    Write-TestResult "  Identifier URI" "Fail" "Not configured"
}

# Check App Roles
Write-Host "`nApp Roles:" -ForegroundColor Yellow
$requiredRoles = @("Administrator", "Manager", "CRMUser", "FleetManager", "FinanceUser", "ReadOnlyUser")

if ($app.appRoles) {
    $configuredRoles = $app.appRoles | ForEach-Object { $_.value }
    
    foreach ($role in $requiredRoles) {
        if ($configuredRoles -contains $role) {
            Write-TestResult "  $role" "Pass"
        } else {
            Write-TestResult "  $role" "Fail" "Not configured"
        }
    }
} else {
    Write-TestResult "  App Roles" "Fail" "No app roles configured"
}

# Test Token Acquisition (if user email provided)
if ($TestUserEmail) {
    Write-Host "`nToken Acquisition Test:" -ForegroundColor Yellow
    Write-Host "  Testing with user: $TestUserEmail" -ForegroundColor Gray
    
    try {
        # Try to get an access token
        $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        
        Write-TestResult "  Token Endpoint" "Info" $tokenEndpoint
        
        # This would require actual authentication - just showing the structure
        Write-TestResult "  Token Acquisition" "Info" "Manual testing required in application"
    }
    catch {
        Write-TestResult "  Token Acquisition" "Fail" $_.Exception.Message
    }
}

# Generate Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$passCount = 0
$failCount = 0
$warningCount = 0

# Count results (simplified for this example)
Write-Host "Results will vary based on configuration" -ForegroundColor Gray

# Recommendations
Write-Host "`nRecommendations:" -ForegroundColor Yellow
Write-Host "1. Ensure admin consent is granted for all permissions"
Write-Host "2. Test token acquisition with a real user account"
Write-Host "3. Verify scopes are being requested correctly in your application"
Write-Host "4. Check audit logs for any permission-related errors"

# Export test results
$testResults = @{
    ApplicationId = $ApplicationId
    TenantId = $TenantId
    TestDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    GraphPermissionsConfigured = ($graphPermissions -ne $null)
    CustomScopesConfigured = ($app.api.oauth2PermissionScopes -ne $null)
    ServicePrincipalExists = ($sp -ne $null)
    IdentifierUriConfigured = ($app.identifierUris -ne $null)
    AppRolesConfigured = ($app.appRoles -ne $null)
}

$resultsFile = "api-permissions-test-results.json"
$testResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $resultsFile -Encoding UTF8
Write-Host "`nTest results saved to: $resultsFile" -ForegroundColor Green