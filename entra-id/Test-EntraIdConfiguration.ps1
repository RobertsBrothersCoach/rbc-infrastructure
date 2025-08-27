<#
.SYNOPSIS
    Tests the Azure Entra ID configuration for Tour Bus Leasing application
    
.DESCRIPTION
    Validates app registration, permissions, security groups, and authentication flow
    
.PARAMETER ApplicationId
    The Application ID to test
    
.PARAMETER TenantId
    The Azure AD tenant ID
    
.PARAMETER Environment
    The environment to test (dev, qa, or prod)
    
.EXAMPLE
    .\Test-EntraIdConfiguration.ps1 -ApplicationId "app-id" -TenantId "tenant-id" -Environment dev
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
    
    [string]$KeyVaultName,
    
    [switch]$TestAuthentication
)

# Test results tracking
$testResults = @{
    Passed = @()
    Failed = @()
    Warnings = @()
}

function Write-TestResult {
    param(
        [string]$TestName,
        [string]$Status,
        [string]$Message = ""
    )
    
    $symbol = switch ($Status) {
        'Pass' { '✓'; $color = 'Green' }
        'Fail' { '✗'; $color = 'Red' }
        'Warning' { '⚠'; $color = 'Yellow' }
        'Info' { 'ℹ'; $color = 'Cyan' }
    }
    
    Write-Host "$symbol $TestName" -ForegroundColor $color
    if ($Message) {
        Write-Host "  $Message" -ForegroundColor Gray
    }
    
    switch ($Status) {
        'Pass' { $testResults.Passed += $TestName }
        'Fail' { $testResults.Failed += $TestName }
        'Warning' { $testResults.Warnings += $TestName }
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Entra ID Configuration Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor White
Write-Host "Application ID: $ApplicationId" -ForegroundColor White
Write-Host "Tenant ID: $TenantId" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

# Test 1: Verify Azure CLI is authenticated
Write-Host "Testing Azure CLI authentication..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if ($account) {
    Write-TestResult "Azure CLI Authentication" "Pass" "Logged in as: $($account.user.name)"
} else {
    Write-TestResult "Azure CLI Authentication" "Fail" "Please run 'az login'"
    exit 1
}

# Test 2: Verify app registration exists
Write-Host "`nTesting app registration..." -ForegroundColor Yellow
$app = az ad app show --id $ApplicationId 2>$null | ConvertFrom-Json
if ($app) {
    Write-TestResult "App Registration" "Pass" "Found: $($app.displayName)"
    
    # Test 2a: Check redirect URIs
    $expectedRedirectUris = switch ($Environment) {
        'dev' { @("http://localhost:3000/auth/callback", "http://localhost:5173/auth/callback") }
        'qa' { @("https://qa-tourbus.azurewebsites.net/auth/callback", "https://qa-tourbus.azurecontainerapps.io/auth/callback") }
        'prod' { @("https://tourbus.azurewebsites.net/auth/callback", "https://tourbus.azurecontainerapps.io/auth/callback") }
    }
    
    $configuredUris = $app.web.redirectUris
    $missingUris = $expectedRedirectUris | Where-Object { $_ -notin $configuredUris }
    
    if ($missingUris.Count -eq 0) {
        Write-TestResult "Redirect URIs" "Pass" "$($configuredUris.Count) URIs configured"
    } else {
        Write-TestResult "Redirect URIs" "Warning" "Missing: $($missingUris -join ', ')"
    }
    
    # Test 2b: Check identifier URI
    if ($app.identifierUris -contains "api://tourbus-$Environment") {
        Write-TestResult "Identifier URI" "Pass" "api://tourbus-$Environment"
    } else {
        Write-TestResult "Identifier URI" "Fail" "Expected: api://tourbus-$Environment"
    }
} else {
    Write-TestResult "App Registration" "Fail" "App not found with ID: $ApplicationId"
    exit 1
}

# Test 3: Verify service principal
Write-Host "`nTesting service principal..." -ForegroundColor Yellow
$sp = az ad sp show --id $ApplicationId 2>$null | ConvertFrom-Json
if ($sp) {
    Write-TestResult "Service Principal" "Pass" "Enterprise app configured"
} else {
    Write-TestResult "Service Principal" "Fail" "Service principal not found"
}

# Test 4: Check API permissions
Write-Host "`nTesting API permissions..." -ForegroundColor Yellow
$requiredPermissions = @(
    "User.Read",
    "openid",
    "profile",
    "email",
    "GroupMember.Read.All"
)

$permissions = az ad app permission list --id $ApplicationId --query "[].{api:resourceAppId,scopes:resourceAccess[].id}" | ConvertFrom-Json
$graphPermissions = $permissions | Where-Object { $_.api -eq "00000003-0000-0000-c000-000000000000" }

if ($graphPermissions) {
    Write-TestResult "API Permissions" "Pass" "Microsoft Graph permissions configured"
} else {
    Write-TestResult "API Permissions" "Warning" "Review API permissions in portal"
}

# Test 5: Check app roles
Write-Host "`nTesting app roles..." -ForegroundColor Yellow
$expectedRoles = @("Administrator", "Manager", "CRMUser", "FleetManager", "FinanceUser", "ReadOnlyUser")
$appRoles = $app.appRoles | Select-Object -ExpandProperty value

$missingRoles = $expectedRoles | Where-Object { $_ -notin $appRoles }
if ($missingRoles.Count -eq 0) {
    Write-TestResult "App Roles" "Pass" "$($appRoles.Count) roles configured"
} else {
    Write-TestResult "App Roles" "Warning" "Missing roles: $($missingRoles -join ', ')"
}

# Test 6: Check security groups
Write-Host "`nTesting security groups..." -ForegroundColor Yellow
$expectedGroups = @(
    "BusLeasing-Administrators-$Environment",
    "BusLeasing-Managers-$Environment",
    "BusLeasing-CRM-Users-$Environment",
    "BusLeasing-Fleet-Managers-$Environment",
    "BusLeasing-Finance-Users-$Environment",
    "BusLeasing-ReadOnly-Users-$Environment"
)

$foundGroups = 0
foreach ($groupName in $expectedGroups) {
    $group = az ad group list --display-name $groupName --query "[0]" 2>$null | ConvertFrom-Json
    if ($group) {
        $foundGroups++
    }
}

if ($foundGroups -eq $expectedGroups.Count) {
    Write-TestResult "Security Groups" "Pass" "All $foundGroups groups exist"
} else {
    Write-TestResult "Security Groups" "Warning" "Found $foundGroups of $($expectedGroups.Count) groups"
}

# Test 7: Check Key Vault secrets (if Key Vault name provided)
if ($KeyVaultName) {
    Write-Host "`nTesting Key Vault secrets..." -ForegroundColor Yellow
    
    $requiredSecrets = @(
        "EntraId-ApplicationId",
        "EntraId-ClientSecret",
        "EntraId-TenantId",
        "EntraId-Authority",
        "EntraId-RedirectUri",
        "EntraId-ApiScope"
    )
    
    $foundSecrets = 0
    foreach ($secretName in $requiredSecrets) {
        $secret = az keyvault secret show --vault-name $KeyVaultName --name $secretName --query "name" 2>$null
        if ($secret) {
            $foundSecrets++
        }
    }
    
    if ($foundSecrets -eq $requiredSecrets.Count) {
        Write-TestResult "Key Vault Secrets" "Pass" "All $foundSecrets secrets configured"
    } else {
        Write-TestResult "Key Vault Secrets" "Warning" "Found $foundSecrets of $($requiredSecrets.Count) secrets"
    }
}

# Test 8: Test authentication flow (optional)
if ($TestAuthentication) {
    Write-Host "`nTesting authentication flow..." -ForegroundColor Yellow
    
    try {
        # Get a token using device code flow
        $tokenResponse = az account get-access-token --resource "api://tourbus-$Environment" 2>$null | ConvertFrom-Json
        
        if ($tokenResponse.accessToken) {
            Write-TestResult "Authentication Flow" "Pass" "Token acquired successfully"
            
            # Decode token to check claims
            $tokenPayload = $tokenResponse.accessToken.Split('.')[1]
            $tokenPayload = $tokenPayload.Replace('-', '+').Replace('_', '/')
            while ($tokenPayload.Length % 4) { $tokenPayload += "=" }
            $claims = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($tokenPayload)) | ConvertFrom-Json
            
            Write-TestResult "Token Claims" "Info" "User: $($claims.unique_name)"
            Write-TestResult "Token Scope" "Info" "Scope: $($claims.scp)"
        } else {
            Write-TestResult "Authentication Flow" "Warning" "Could not acquire token"
        }
    } catch {
        Write-TestResult "Authentication Flow" "Warning" "Manual test required in portal"
    }
}

# Generate summary report
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✓ Passed: $($testResults.Passed.Count)" -ForegroundColor Green
Write-Host "⚠ Warnings: $($testResults.Warnings.Count)" -ForegroundColor Yellow
Write-Host "✗ Failed: $($testResults.Failed.Count)" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Cyan

if ($testResults.Failed.Count -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    foreach ($test in $testResults.Failed) {
        Write-Host "  - $test" -ForegroundColor Red
    }
}

if ($testResults.Warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    foreach ($test in $testResults.Warnings) {
        Write-Host "  - $test" -ForegroundColor Yellow
    }
}

# Export test results
$testReport = @{
    TestDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Environment = $Environment
    ApplicationId = $ApplicationId
    TenantId = $TenantId
    Results = $testResults
    Summary = @{
        TotalTests = $testResults.Passed.Count + $testResults.Failed.Count + $testResults.Warnings.Count
        Passed = $testResults.Passed.Count
        Failed = $testResults.Failed.Count
        Warnings = $testResults.Warnings.Count
    }
}

$reportFile = "entra-id-test-results-$Environment-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$testReport | ConvertTo-Json -Depth 10 | Out-File $reportFile
Write-Host "`nTest report saved to: $reportFile" -ForegroundColor Cyan

# Exit with appropriate code
if ($testResults.Failed.Count -gt 0) {
    exit 1
} else {
    exit 0
}