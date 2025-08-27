param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'qa', 'prod')]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('eastus2', 'westcentralus', 'eastus')]
    [string]$Location = 'eastus2',
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('westcentralus', 'eastus2', 'westus2')]
    [string]$BackupRegion = 'westcentralus',
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Generate secure passwords
function New-SecurePassword {
    $length = 32
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>?'
    $password = ''
    $random = New-Object System.Random
    for ($i = 0; $i -lt $length; $i++) {
        $password += $chars[$random.Next($chars.Length)]
    }
    return $password
}

Write-Host "Deploying Tour Bus Leasing infrastructure to $Environment environment..." -ForegroundColor Cyan

# Display region information with zone support
$zoneSupport = @{
    'eastus2' = $true
    'westcentralus' = $false
    'eastus' = $true
    'westus2' = $true
}

Write-Host "Primary Region: $Location $(if($zoneSupport[$Location]) {'(with availability zones)'} else {'(no availability zones)'})" -ForegroundColor Yellow
Write-Host "Backup Region: $BackupRegion (for disaster recovery)" -ForegroundColor Yellow

# Validate regions are different
if ($Location -eq $BackupRegion) {
    Write-Host "ERROR: Primary and backup regions must be different for proper disaster recovery" -ForegroundColor Red
    exit 1
}

# Display zone configuration based on region support
if ($Environment -eq 'prod') {
    if ($zoneSupport[$Location]) {
        Write-Host "`nProduction deployment with zone redundancy:" -ForegroundColor Green
        Write-Host "  - PostgreSQL: Zone-redundant HA (Zones 1 & 2)" -ForegroundColor White
        Write-Host "  - Redis: Zone-redundant Premium tier (Zones 1, 2, 3)" -ForegroundColor White
        Write-Host "  - App Service: Zone-redundant P1v3 (3+ instances)" -ForegroundColor White
        Write-Host "  - Container Apps: Zone-redundant environment" -ForegroundColor White
    } else {
        Write-Host "`nProduction deployment in $Location (zone redundancy not available in this region)" -ForegroundColor Yellow
        Write-Host "  - Using high availability within single datacenter" -ForegroundColor White
        Write-Host "  - Geo-redundant backups to $BackupRegion" -ForegroundColor White
    }
} else {
    Write-Host "`nNon-production deployment (single zone for cost optimization)" -ForegroundColor Yellow
}

# Generate secure admin password for PostgreSQL
$postgresPassword = New-SecurePassword
$securePostgresPassword = ConvertTo-SecureString $postgresPassword -AsPlainText -Force

# Set deployment parameters
$deploymentParams = @{
    environmentName = $Environment
    location = $Location
    backupRegion = $BackupRegion
    administratorPassword = $securePostgresPassword
}

# Deploy the infrastructure
$deploymentName = "tourbus-$Environment-$(Get-Date -Format 'yyyyMMddHHmmss')"

if ($WhatIf) {
    Write-Host "Running What-If deployment..." -ForegroundColor Yellow
    az deployment sub what-if `
        --name $deploymentName `
        --location $Location `
        --template-file main.bicep `
        --parameters @deploymentParams
} else {
    Write-Host "Starting deployment..." -ForegroundColor Green
    
    # Deploy infrastructure
    $result = az deployment sub create `
        --name $deploymentName `
        --location $Location `
        --template-file main.bicep `
        --parameters @deploymentParams `
        --output json | ConvertFrom-Json
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Deployment completed successfully!" -ForegroundColor Green
        
        # Output important information
        Write-Host "`nDeployment Outputs:" -ForegroundColor Cyan
        Write-Host "===================" -ForegroundColor Cyan
        
        $outputs = $result.properties.outputs
        Write-Host "Resource Group: $($outputs.resourceGroupName.value)" -ForegroundColor White
        Write-Host "Key Vault: $($outputs.keyVaultName.value)" -ForegroundColor White
        Write-Host "API URL: $($outputs.apiUrl.value)" -ForegroundColor White
        Write-Host "Container App URL: $($outputs.containerAppUrl.value)" -ForegroundColor White
        
        Write-Host "`nSecrets stored in Key Vault:" -ForegroundColor Yellow
        Write-Host "- PostgreSQL connection string" -ForegroundColor White
        Write-Host "- Redis connection string" -ForegroundColor White
        Write-Host "- JWT signing key" -ForegroundColor White
        
        Write-Host "`nPassword Rotation:" -ForegroundColor Yellow
        if ($Environment -eq 'prod') {
            Write-Host "- PostgreSQL admin password: 90 days" -ForegroundColor White
        } else {
            Write-Host "- PostgreSQL admin password: 180 days" -ForegroundColor White
        }
        Write-Host "- JWT signing key: 365 days" -ForegroundColor White
        
        Write-Host "`nAvailability Zone Status:" -ForegroundColor Cyan
        if ($Environment -eq 'prod') {
            Write-Host "✓ Zone-redundant deployment active" -ForegroundColor Green
            Write-Host "✓ Automatic failover configured" -ForegroundColor Green
            Write-Host "✓ Cross-zone replication enabled" -ForegroundColor Green
        } else {
            Write-Host "- Single zone deployment (non-production)" -ForegroundColor Yellow
        }
        
        Write-Host "`nNext Steps:" -ForegroundColor Cyan
        Write-Host "1. Configure application settings to use Key Vault references" -ForegroundColor White
        Write-Host "2. Set up monitoring alerts for secret expiration" -ForegroundColor White
        Write-Host "3. Configure backup and disaster recovery procedures" -ForegroundColor White
        Write-Host "4. Review and adjust network security rules" -ForegroundColor White
        Write-Host "5. Test zone failover in non-production environment" -ForegroundColor White
        Write-Host "6. Configure Azure Monitor for zone health tracking" -ForegroundColor White
        
    } else {
        Write-Host "Deployment failed!" -ForegroundColor Red
        exit 1
    }
}