<#
.SYNOPSIS
    Registers and configures an application in Azure Entra ID for Tour Bus Leasing
    
.DESCRIPTION
    This script creates an app registration, configures permissions, creates security groups,
    and stores credentials in Azure Key Vault
    
.PARAMETER Environment
    The environment to configure (dev, qa, or prod)
    
.PARAMETER TenantId
    The Azure AD tenant ID
    
.PARAMETER KeyVaultName
    The name of the Key Vault to store secrets
    
.EXAMPLE
    .\Register-EntraIdApplication.ps1 -Environment dev -TenantId "your-tenant-id" -KeyVaultName "kv-tourbus-dev"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('dev', 'qa', 'prod')]
    [string]$Environment,
    
    [Parameter(Mandatory = $true)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,
    
    [switch]$CreateSecurityGroups,
    
    [switch]$SkipKeyVault
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import required modules
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module Az.KeyVault -ErrorAction Stop

# Configuration
$appDisplayName = "Tour Bus Leasing Management $($Environment.ToUpper())"
$identifierUri = "api://tourbus-$Environment"

# Define redirect URIs based on environment
$redirectUris = switch ($Environment) {
    'dev' {
        @(
            "http://localhost:3000/auth/callback"
            "http://localhost:5173/auth/callback"
            "https://localhost:7000/auth/callback"
        )
    }
    'qa' {
        @(
            "https://qa-tourbus.azurewebsites.net/auth/callback"
            "https://qa-tourbus.azurecontainerapps.io/auth/callback"
        )
    }
    'prod' {
        @(
            "https://tourbus.azurewebsites.net/auth/callback"
            "https://tourbus.azurecontainerapps.io/auth/callback"
            "https://www.tourbus-leasing.com/auth/callback"
        )
    }
}

# SPA redirect URIs (for React app)
$spaRedirectUris = switch ($Environment) {
    'dev' {
        @(
            "http://localhost:3000"
            "http://localhost:5173"
        )
    }
    'qa' {
        @(
            "https://qa-tourbus.azurecontainerapps.io"
        )
    }
    'prod' {
        @(
            "https://tourbus.azurecontainerapps.io"
            "https://www.tourbus-leasing.com"
        )
    }
}

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

# Connect to Azure
Write-Log "Connecting to Azure..." -Level Info
try {
    $context = Get-AzContext
    if (-not $context) {
        Connect-AzAccount -TenantId $TenantId
    }
    Set-AzContext -TenantId $TenantId
    Write-Log "Connected to Azure tenant: $TenantId" -Level Success
} catch {
    Write-Log "Failed to connect to Azure: $_" -Level Error
    exit 1
}

# Check if app already exists
Write-Log "Checking for existing app registration..." -Level Info
$existingApp = az ad app list --display-name "$appDisplayName" --query "[0]" | ConvertFrom-Json

if ($existingApp) {
    Write-Log "App registration already exists with ID: $($existingApp.appId)" -Level Warning
    $confirmation = Read-Host "Do you want to update the existing app? (yes/no)"
    if ($confirmation -ne 'yes') {
        Write-Log "Exiting without changes" -Level Info
        exit 0
    }
    $appId = $existingApp.appId
    $updateExisting = $true
} else {
    $updateExisting = $false
}

# Create or update app registration
try {
    if ($updateExisting) {
        Write-Log "Updating existing app registration..." -Level Info
        
        # Update redirect URIs
        az ad app update --id $appId `
            --web-redirect-uris $redirectUris `
            --enable-id-token-issuance true `
            --identifier-uris $identifierUri
            
        # Update SPA redirect URIs
        foreach ($uri in $spaRedirectUris) {
            az ad app update --id $appId --set spa.redirectUris+="['$uri']" 2>$null
        }
        
    } else {
        Write-Log "Creating new app registration: $appDisplayName" -Level Info
        
        # Create the app
        $app = az ad app create `
            --display-name "$appDisplayName" `
            --sign-in-audience "AzureADMyOrg" `
            --web-redirect-uris $redirectUris `
            --enable-id-token-issuance true `
            --identifier-uris $identifierUri `
            --query "{appId:appId, objectId:id}" | ConvertFrom-Json
            
        $appId = $app.appId
        
        # Add SPA redirect URIs
        foreach ($uri in $spaRedirectUris) {
            az ad app update --id $appId --set spa.redirectUris+="['$uri']" 2>$null
        }
        
        Write-Log "App registration created with ID: $appId" -Level Success
    }
    
    # Configure API permissions
    Write-Log "Configuring API permissions..." -Level Info
    
    # Microsoft Graph permissions
    $graphPermissions = @(
        "e1fe6dd8-ba31-4d61-89e7-88639da4683d", # User.Read
        "37f7f235-527c-4136-accd-4a02d197296e", # openid
        "14dad69e-099b-42c9-810b-d002981feec1", # profile
        "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0", # email
        "98830695-27a2-44f7-8c18-0c3ebc9698f6"  # GroupMember.Read.All
    )
    
    foreach ($permission in $graphPermissions) {
        az ad app permission add --id $appId `
            --api "00000003-0000-0000-c000-000000000000" `
            --api-permissions "$permission=Scope" 2>$null
    }
    
    Write-Log "API permissions configured" -Level Success
    
    # Create app roles
    Write-Log "Creating app roles..." -Level Info
    
    $appRoles = @"
[
    {
        "allowedMemberTypes": ["User"],
        "description": "Full system access and administrative privileges",
        "displayName": "Administrator",
        "isEnabled": true,
        "value": "Administrator"
    },
    {
        "allowedMemberTypes": ["User"],
        "description": "Management level access to all modules",
        "displayName": "Manager",
        "isEnabled": true,
        "value": "Manager"
    },
    {
        "allowedMemberTypes": ["User"],
        "description": "Access to CRM module for client management",
        "displayName": "CRM User",
        "isEnabled": true,
        "value": "CRMUser"
    },
    {
        "allowedMemberTypes": ["User"],
        "description": "Access to fleet management and maintenance modules",
        "displayName": "Fleet Manager",
        "isEnabled": true,
        "value": "FleetManager"
    },
    {
        "allowedMemberTypes": ["User"],
        "description": "Access to financial and reporting modules",
        "displayName": "Finance User",
        "isEnabled": true,
        "value": "FinanceUser"
    },
    {
        "allowedMemberTypes": ["User"],
        "description": "Read-only access to all modules",
        "displayName": "Read Only User",
        "isEnabled": true,
        "value": "ReadOnlyUser"
    }
]
"@
    
    $appRoles | Out-File -FilePath "app-roles-temp.json" -Encoding UTF8
    az ad app update --id $appId --app-roles "@app-roles-temp.json"
    Remove-Item "app-roles-temp.json" -Force
    
    Write-Log "App roles created" -Level Success
    
    # Create service principal (Enterprise Application)
    Write-Log "Creating service principal..." -Level Info
    $sp = az ad sp list --filter "appId eq '$appId'" --query "[0]" | ConvertFrom-Json
    
    if (-not $sp) {
        $sp = az ad sp create --id $appId | ConvertFrom-Json
        Write-Log "Service principal created" -Level Success
    } else {
        Write-Log "Service principal already exists" -Level Info
    }
    
    # Create client secret
    Write-Log "Creating client secret..." -Level Info
    $secretName = "TourBusLeasing-$Environment-Secret"
    $secret = az ad app credential reset --id $appId `
        --display-name $secretName `
        --years 2 `
        --query "{password:password, endDate:endDate}" | ConvertFrom-Json
    
    Write-Log "Client secret created (expires: $($secret.endDate))" -Level Success
    
    # Store in Key Vault
    if (-not $SkipKeyVault) {
        Write-Log "Storing credentials in Key Vault..." -Level Info
        
        try {
            # Store Application ID
            Set-AzKeyVaultSecret -VaultName $KeyVaultName `
                -Name "EntraId-ApplicationId" `
                -SecretValue (ConvertTo-SecureString $appId -AsPlainText -Force) `
                -Tag @{Environment=$Environment; Purpose="Authentication"} | Out-Null
            
            # Store Client Secret
            Set-AzKeyVaultSecret -VaultName $KeyVaultName `
                -Name "EntraId-ClientSecret" `
                -SecretValue (ConvertTo-SecureString $secret.password -AsPlainText -Force) `
                -Tag @{Environment=$Environment; Purpose="Authentication"; ExpiresOn=$secret.endDate} | Out-Null
            
            # Store Tenant ID
            Set-AzKeyVaultSecret -VaultName $KeyVaultName `
                -Name "EntraId-TenantId" `
                -SecretValue (ConvertTo-SecureString $TenantId -AsPlainText -Force) `
                -Tag @{Environment=$Environment; Purpose="Authentication"} | Out-Null
            
            Write-Log "Credentials stored in Key Vault: $KeyVaultName" -Level Success
        } catch {
            Write-Log "Failed to store in Key Vault: $_" -Level Error
            Write-Log "Please manually store the credentials" -Level Warning
        }
    }
    
    # Create security groups if requested
    if ($CreateSecurityGroups) {
        Write-Log "Creating security groups..." -Level Info
        
        $groups = @(
            @{Name="BusLeasing-Administrators-$Environment"; Description="Full system access and administrative privileges"}
            @{Name="BusLeasing-Managers-$Environment"; Description="Management level access to all modules"}
            @{Name="BusLeasing-CRM-Users-$Environment"; Description="Access to CRM module for client management"}
            @{Name="BusLeasing-Fleet-Managers-$Environment"; Description="Access to fleet management and maintenance modules"}
            @{Name="BusLeasing-Finance-Users-$Environment"; Description="Access to financial and reporting modules"}
            @{Name="BusLeasing-ReadOnly-Users-$Environment"; Description="Read-only access to all modules"}
        )
        
        foreach ($group in $groups) {
            $existingGroup = az ad group list --display-name $group.Name --query "[0]" | ConvertFrom-Json
            
            if (-not $existingGroup) {
                az ad group create --display-name $group.Name `
                    --mail-nickname $group.Name.Replace("-", "") `
                    --description $group.Description | Out-Null
                    
                Write-Log "Created group: $($group.Name)" -Level Success
            } else {
                Write-Log "Group already exists: $($group.Name)" -Level Info
            }
        }
    }
    
    # Output summary
    Write-Log "`n========================================" -Level Info
    Write-Log "App Registration Summary" -Level Success
    Write-Log "========================================" -Level Info
    Write-Log "Display Name: $appDisplayName" -Level Info
    Write-Log "Application ID: $appId" -Level Info
    Write-Log "Tenant ID: $TenantId" -Level Info
    Write-Log "Identifier URI: $identifierUri" -Level Info
    Write-Log "Key Vault: $KeyVaultName" -Level Info
    Write-Log "Environment: $Environment" -Level Info
    Write-Log "========================================" -Level Info
    
    # Save configuration to file
    $config = @{
        ApplicationId = $appId
        TenantId = $TenantId
        DisplayName = $appDisplayName
        IdentifierUri = $identifierUri
        RedirectUris = $redirectUris
        SpaRedirectUris = $spaRedirectUris
        KeyVaultName = $KeyVaultName
        Environment = $Environment
        CreatedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
    
    $configFile = "entra-id-config-$Environment.json"
    $config | ConvertTo-Json -Depth 10 | Out-File $configFile
    Write-Log "Configuration saved to: $configFile" -Level Success
    
} catch {
    Write-Log "Failed to configure app registration: $_" -Level Error
    exit 1
}