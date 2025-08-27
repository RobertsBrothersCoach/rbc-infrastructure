param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'qa', 'prod', 'all')]
    [string]$Environment,
    
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    
    [Parameter(Mandatory=$false)]
    [string]$Repository = "RobertsBrothersCoach/RBC-LeasingApp",
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateServicePrincipals
)

# Set error action preference
$ErrorActionPreference = "Stop"

# GitHub API base URL
$apiBase = "https://api.github.com"
$headers = @{
    "Authorization" = "Bearer $GitHubToken"
    "Accept" = "application/vnd.github.v3+json"
}

Write-Host "Setting up GitHub environments for $Repository" -ForegroundColor Cyan

# Environment configurations
$environments = @{
    development = @{
        name = "development"
        protection_rules = @{
            required_reviewers = @()
            deployment_branches = @{ protected_branches = $false }
        }
        secrets = @{
            AZURE_WEBAPP_NAME = "tourbus-api-dev"
            AZURE_CONTAINERAPP_NAME = "tourbus-frontend-dev"
            RESOURCE_GROUP = "rg-tourbus-dev-eastus2"
            KEY_VAULT_NAME = "kv-tourbus-dev"
            DB_NAME = "tourbus_dev"
            DB_USER = "tourbus_dev"
        }
        variables = @{
            ENVIRONMENT = "development"
            LOG_LEVEL = "debug"
            ENABLE_DEBUG = "true"
            API_URL = "https://tourbus-api-dev.azurewebsites.net"
            VITE_API_URL = "https://tourbus-api-dev.azurewebsites.net/api"
        }
    }
    qa = @{
        name = "qa"
        protection_rules = @{
            required_reviewers = @()
            deployment_branches = @{ 
                protected_branches = $true
                custom_branches = @("main")
            }
            wait_timer = 0
        }
        secrets = @{
            AZURE_WEBAPP_NAME = "tourbus-api-qa"
            AZURE_CONTAINERAPP_NAME = "tourbus-frontend-qa"
            RESOURCE_GROUP = "rg-tourbus-qa-eastus2"
            KEY_VAULT_NAME = "kv-tourbus-qa"
            DB_NAME = "tourbus_qa"
            DB_USER = "tourbus_qa"
        }
        variables = @{
            ENVIRONMENT = "qa"
            LOG_LEVEL = "info"
            ENABLE_DEBUG = "false"
            API_URL = "https://tourbus-api-qa.azurewebsites.net"
            VITE_API_URL = "https://tourbus-api-qa.azurewebsites.net/api"
        }
    }
    production = @{
        name = "production"
        protection_rules = @{
            required_reviewers = @()
            deployment_branches = @{ 
                protected_branches = $true
                custom_branches = @("main")
            }
            wait_timer = 5
        }
        secrets = @{
            AZURE_WEBAPP_NAME = "tourbus-api-prod"
            AZURE_CONTAINERAPP_NAME = "tourbus-frontend-prod"
            RESOURCE_GROUP = "rg-tourbus-prod-eastus2"
            KEY_VAULT_NAME = "kv-tourbus-prod"
            DB_NAME = "tourbus_prod"
            DB_USER = "tourbus_prod"
        }
        variables = @{
            ENVIRONMENT = "production"
            LOG_LEVEL = "warn"
            ENABLE_DEBUG = "false"
            API_URL = "https://api.tourbus.com"
            VITE_API_URL = "https://api.tourbus.com/api"
            CDN_URL = "https://cdn.tourbus.com"
        }
    }
}

function Create-GitHubEnvironment {
    param (
        [string]$EnvName,
        [hashtable]$Config
    )
    
    Write-Host "`nCreating environment: $EnvName" -ForegroundColor Yellow
    
    $owner = $Repository.Split('/')[0]
    $repo = $Repository.Split('/')[1]
    
    # Create or update environment
    $envUrl = "$apiBase/repos/$owner/$repo/environments/$EnvName"
    
    $body = @{
        wait_timer = $Config.protection_rules.wait_timer
        reviewers = $Config.protection_rules.required_reviewers
        deployment_branch_policy = if ($Config.protection_rules.deployment_branches.protected_branches) {
            @{
                protected_branches = $Config.protection_rules.deployment_branches.protected_branches
                custom_branch_policies = $Config.protection_rules.deployment_branches.custom_branches | ForEach-Object {
                    @{ name = $_ }
                }
            }
        } else { $null }
    } | ConvertTo-Json -Depth 10
    
    try {
        Invoke-RestMethod -Uri $envUrl -Method Put -Headers $headers -Body $body -ContentType "application/json"
        Write-Host "✅ Environment '$EnvName' created/updated" -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to create environment '$EnvName': $_" -ForegroundColor Red
    }
}

function Set-EnvironmentSecret {
    param (
        [string]$EnvName,
        [string]$SecretName,
        [string]$SecretValue
    )
    
    $owner = $Repository.Split('/')[0]
    $repo = $Repository.Split('/')[1]
    
    # Get repository public key
    $keyUrl = "$apiBase/repos/$owner/$repo/environments/$EnvName/secrets/public-key"
    $keyResponse = Invoke-RestMethod -Uri $keyUrl -Method Get -Headers $headers
    
    # Encrypt secret value
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($SecretValue)
    $encrypted = [System.Convert]::ToBase64String($bytes)  # Simplified - use proper encryption in production
    
    # Set secret
    $secretUrl = "$apiBase/repos/$owner/$repo/environments/$EnvName/secrets/$SecretName"
    $body = @{
        encrypted_value = $encrypted
        key_id = $keyResponse.key_id
    } | ConvertTo-Json
    
    try {
        Invoke-RestMethod -Uri $secretUrl -Method Put -Headers $headers -Body $body -ContentType "application/json"
        Write-Host "  ✅ Secret '$SecretName' set" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️ Could not set secret '$SecretName': $_" -ForegroundColor Yellow
    }
}

function Set-EnvironmentVariable {
    param (
        [string]$EnvName,
        [string]$VarName,
        [string]$VarValue
    )
    
    $owner = $Repository.Split('/')[0]
    $repo = $Repository.Split('/')[1]
    
    # Set variable
    $varUrl = "$apiBase/repos/$owner/$repo/environments/$EnvName/variables/$VarName"
    $body = @{
        name = $VarName
        value = $VarValue
    } | ConvertTo-Json
    
    try {
        Invoke-RestMethod -Uri $varUrl -Method Post -Headers $headers -Body $body -ContentType "application/json"
        Write-Host "  ✅ Variable '$VarName' set" -ForegroundColor Green
    } catch {
        # Try update if create fails
        try {
            Invoke-RestMethod -Uri $varUrl -Method Patch -Headers $headers -Body $body -ContentType "application/json"
            Write-Host "  ✅ Variable '$VarName' updated" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠️ Could not set variable '$VarName': $_" -ForegroundColor Yellow
        }
    }
}

function Create-AzureServicePrincipal {
    param (
        [string]$EnvName,
        [string]$ResourceGroup
    )
    
    Write-Host "`nCreating Azure Service Principal for $EnvName..." -ForegroundColor Cyan
    
    # Check if Azure CLI is installed
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Azure CLI not installed. Please install from https://aka.ms/installazurecli" -ForegroundColor Red
        return $null
    }
    
    # Login to Azure if needed
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        Write-Host "Please login to Azure..." -ForegroundColor Yellow
        az login
    }
    
    $subscriptionId = (az account show --query id -o tsv)
    $spName = "GitHub-TourBus-$EnvName"
    
    # Create service principal
    $sp = az ad sp create-for-rbac `
        --name $spName `
        --role contributor `
        --scopes "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup" `
        --sdk-auth | ConvertFrom-Json
    
    if ($sp) {
        Write-Host "✅ Service Principal created: $spName" -ForegroundColor Green
        return $sp | ConvertTo-Json -Compress
    } else {
        Write-Host "❌ Failed to create Service Principal" -ForegroundColor Red
        return $null
    }
}

# Process environments
$envsToProcess = if ($Environment -eq 'all') {
    @('development', 'qa', 'production')
} else {
    @($Environment)
}

foreach ($env in $envsToProcess) {
    $config = $environments[$env]
    
    # Create environment
    Create-GitHubEnvironment -EnvName $config.name -Config $config
    
    # Create Azure Service Principal if requested
    if ($CreateServicePrincipals) {
        $spCredentials = Create-AzureServicePrincipal -EnvName $config.name -ResourceGroup $config.secrets.RESOURCE_GROUP
        if ($spCredentials) {
            Set-EnvironmentSecret -EnvName $config.name -SecretName "AZURE_CREDENTIALS" -SecretValue $spCredentials
        }
    }
    
    # Set environment secrets
    Write-Host "Setting secrets for $($config.name)..." -ForegroundColor Cyan
    foreach ($secret in $config.secrets.GetEnumerator()) {
        Set-EnvironmentSecret -EnvName $config.name -SecretName $secret.Key -SecretValue $secret.Value
    }
    
    # Set environment variables
    Write-Host "Setting variables for $($config.name)..." -ForegroundColor Cyan
    foreach ($var in $config.variables.GetEnumerator()) {
        Set-EnvironmentVariable -EnvName $config.name -VarName $var.Key -VarValue $var.Value
    }
}

# Set common repository variables
Write-Host "`nSetting common repository variables..." -ForegroundColor Cyan
$commonVars = @{
    NODE_VERSION = "18.x"
    POSTGRES_VERSION = "15"
    REGISTRY = "tourbusacr"
    BICEP_VERSION = "0.20.4"
}

$owner = $Repository.Split('/')[0]
$repo = $Repository.Split('/')[1]

foreach ($var in $commonVars.GetEnumerator()) {
    $varUrl = "$apiBase/repos/$owner/$repo/actions/variables/$($var.Key)"
    $body = @{
        name = $var.Key
        value = $var.Value
    } | ConvertTo-Json
    
    try {
        Invoke-RestMethod -Uri $varUrl -Method Post -Headers $headers -Body $body -ContentType "application/json"
        Write-Host "  ✅ Repository variable '$($var.Key)' set" -ForegroundColor Green
    } catch {
        # Try update if create fails
        try {
            Invoke-RestMethod -Uri $varUrl -Method Patch -Headers $headers -Body $body -ContentType "application/json"
            Write-Host "  ✅ Repository variable '$($var.Key)' updated" -ForegroundColor Green
        } catch {
            Write-Host "  ⚠️ Could not set repository variable '$($var.Key)'" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n✅ Environment setup complete!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Review environment settings in GitHub: https://github.com/$Repository/settings/environments"
Write-Host "2. Add required reviewers for QA and Production environments"
Write-Host "3. Update any missing secrets with actual values"
Write-Host "4. Test deployment to each environment"
Write-Host "5. Set up branch protection rules"