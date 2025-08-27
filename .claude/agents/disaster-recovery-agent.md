# Disaster Recovery Agent

## Purpose
Expert agent for handling backup, recovery, and high availability configurations in the RBC-Infrastructure repository.

## Capabilities
- Configure geo-redundant backups
- Set up failover procedures
- Test zone redundancy
- Manage backup regions
- Configure RPO/RTO settings
- Implement disaster recovery runbooks

## Recovery Objectives

### RTO/RPO Targets
| Service | RTO (Recovery Time) | RPO (Recovery Point) | Strategy |
|---------|--------------------|--------------------|----------|
| PostgreSQL | 1 hour | 5 minutes | Geo-redundant backup + Read replica |
| Redis Cache | 30 minutes | 1 hour | Premium tier with geo-replication |
| AKS Cluster | 2 hours | Real-time | Multi-region with GitOps |
| App Service | 30 minutes | Real-time | Zone redundancy + Traffic Manager |
| Key Vault | 15 minutes | Real-time | Soft-delete + Backup |
| Container Registry | 1 hour | Daily | Geo-replication |

## Zone Redundancy Configuration

### Production Zone Setup
```bicep
// bicep/modules/zone-redundancy.bicep
param location string
param environmentName string

var zoneRedundant = environmentName == 'prod' && contains([
  'eastus2'
  'eastus'
  'westus2'
  'centralus'
], location)

// PostgreSQL with Zone Redundancy
resource postgresqlServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' = if (zoneRedundant) {
  name: 'psql-rbc-${environmentName}'
  location: location
  sku: {
    name: 'Standard_D4ds_v4'
    tier: 'GeneralPurpose'
  }
  properties: {
    version: '15'
    highAvailability: {
      mode: 'ZoneRedundant'
      standbyAvailabilityZone: '2'
    }
    availabilityZone: '1'
    backup: {
      backupRetentionDays: 35
      geoRedundantBackup: 'Enabled'
    }
  }
}

// Redis with Zone Redundancy
resource redisCache 'Microsoft.Cache/Redis@2023-08-01' = if (zoneRedundant) {
  name: 'redis-rbc-${environmentName}'
  location: location
  properties: {
    sku: {
      name: 'Premium'
      family: 'P'
      capacity: 1
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    zones: ['1', '2', '3']
    replicasPerMaster: 2
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
    }
  }
}
```

### Zone Failover Testing
```powershell
# Test PostgreSQL failover
az postgres flexible-server restart --resource-group RBCLeasingApp-Prod --name psql-rbc-prod --failover Forced

# Verify zone after failover
az postgres flexible-server show --resource-group RBCLeasingApp-Prod --name psql-rbc-prod --query "availabilityZone"

# Test App Service zone resilience
az webapp show --resource-group RBCLeasingApp-Prod --name app-rbc-prod --query "properties.availabilityState"
```

## Backup Configuration

### PostgreSQL Backup Strategy
```bicep
resource postgresqlBackup 'Microsoft.DBforPostgreSQL/flexibleServers/backups@2023-03-01-preview' = {
  parent: postgresqlServer
  name: 'backup-policy'
  properties: {
    backupRetentionDays: environmentName == 'prod' ? 35 : 7
    geoRedundantBackup: environmentName == 'prod' ? 'Enabled' : 'Disabled'
  }
}

// Long-term retention with Azure Backup
resource backupVault 'Microsoft.DataProtection/backupVaults@2023-01-01' = {
  name: 'bv-rbc-${environmentName}'
  location: location
  properties: {
    storageSettings: [
      {
        datastoreType: 'VaultStore'
        type: environmentName == 'prod' ? 'GeoRedundant' : 'LocallyRedundant'
      }
    ]
  }
}
```

### Automated Backup Scripts
```powershell
# PostgreSQL backup script
param(
    [string]$ResourceGroup = "RBCLeasingApp-Prod",
    [string]$ServerName = "psql-rbc-prod",
    [string]$BackupName = "manual-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
)

# Create on-demand backup
az postgres flexible-server backup create `
    --resource-group $ResourceGroup `
    --name $ServerName `
    --backup-name $BackupName

# Export to storage account for long-term retention
$storageAccount = "strbcbackupprod"
$container = "postgresql-backups"

az postgres flexible-server backup export `
    --resource-group $ResourceGroup `
    --name $ServerName `
    --backup-name $BackupName `
    --storage-account $storageAccount `
    --storage-container $container
```

## Multi-Region Deployment

### Traffic Manager Configuration
```bicep
resource trafficManager 'Microsoft.Network/trafficManagerProfiles@2022-04-01' = {
  name: 'tm-rbc-${environmentName}'
  location: 'global'
  properties: {
    profileStatus: 'Enabled'
    trafficRoutingMethod: 'Priority'
    dnsConfig: {
      relativeName: 'rbc-${environmentName}'
      ttl: 60
    }
    monitorConfig: {
      protocol: 'HTTPS'
      port: 443
      path: '/health'
      intervalInSeconds: 30
      toleratedNumberOfFailures: 3
      timeoutInSeconds: 10
    }
    endpoints: [
      {
        name: 'primary-eastus2'
        type: 'Microsoft.Network/trafficManagerProfiles/azureEndpoints'
        properties: {
          targetResourceId: primaryAppService.id
          priority: 1
          endpointStatus: 'Enabled'
        }
      }
      {
        name: 'secondary-westcentralus'
        type: 'Microsoft.Network/trafficManagerProfiles/azureEndpoints'
        properties: {
          targetResourceId: secondaryAppService.id
          priority: 2
          endpointStatus: 'Enabled'
        }
      }
    ]
  }
}
```

### Cross-Region Replication
```bicep
// Container Registry geo-replication
resource acrReplication 'Microsoft.ContainerRegistry/registries/replications@2023-01-01-preview' = {
  parent: containerRegistry
  name: backupRegion
  location: backupRegion
  properties: {
    zoneRedundancy: environmentName == 'prod' ? 'Enabled' : 'Disabled'
  }
}

// Storage Account geo-replication
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'strbc${environmentName}'
  location: location
  sku: {
    name: environmentName == 'prod' ? 'Standard_GRS' : 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}
```

## Disaster Recovery Runbooks

### PostgreSQL Failover Runbook
```powershell
# 1. Check current primary status
$primaryStatus = az postgres flexible-server show `
    --resource-group RBCLeasingApp-Prod `
    --name psql-rbc-prod `
    --query "state" -o tsv

if ($primaryStatus -ne "Ready") {
    Write-Host "Primary database is not available. Initiating failover..."
    
    # 2. Promote read replica
    az postgres flexible-server replica promote `
        --resource-group RBCLeasingApp-Prod `
        --name psql-rbc-prod-replica `
        --promote-mode standalone
    
    # 3. Update connection strings in Key Vault
    az keyvault secret set `
        --vault-name kv-rbc-prod `
        --name "database-connection" `
        --value "Host=psql-rbc-prod-replica.postgres.database.azure.com;..."
    
    # 4. Restart applications
    az webapp restart --resource-group RBCLeasingApp-Prod --name app-rbc-prod
    
    # 5. Verify application health
    $health = Invoke-WebRequest -Uri "https://app.yourdomain.com/health" -UseBasicParsing
    if ($health.StatusCode -eq 200) {
        Write-Host "Failover completed successfully"
    }
}
```

### AKS Cluster Recovery
```bash
#!/bin/bash
# AKS Disaster Recovery Script

PRIMARY_RG="RBCLeasingApp-Prod"
BACKUP_RG="RBCLeasingApp-Prod-DR"
PRIMARY_CLUSTER="aks-rbc-prod"
BACKUP_CLUSTER="aks-rbc-prod-dr"

# 1. Check primary cluster health
PRIMARY_STATUS=$(az aks show -g $PRIMARY_RG -n $PRIMARY_CLUSTER --query "powerState.code" -o tsv)

if [ "$PRIMARY_STATUS" != "Running" ]; then
    echo "Primary cluster is down. Initiating DR..."
    
    # 2. Ensure backup cluster is running
    az aks start -g $BACKUP_RG -n $BACKUP_CLUSTER
    
    # 3. Update kubeconfig
    az aks get-credentials -g $BACKUP_RG -n $BACKUP_CLUSTER --overwrite-existing
    
    # 4. Apply GitOps configuration to backup cluster
    kubectl apply -f kubernetes/argocd/applications/app-of-apps.yaml
    
    # 5. Update DNS to point to backup cluster
    az network dns record-set a update \
        --resource-group DNS-RG \
        --zone-name yourdomain.com \
        --name app \
        --set ARecords[0].ipv4Address=$(kubectl get service -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    
    echo "DR activation complete"
fi
```

## Backup Validation

### Automated Backup Testing
```yaml
# .github/workflows/backup-validation.yml
name: Backup Validation

on:
  schedule:
    - cron: '0 3 * * 0'  # Weekly on Sunday at 3 AM

jobs:
  test-restore:
    runs-on: ubuntu-latest
    steps:
      - name: Create test resource group
        run: |
          az group create --name RBC-BackupTest --location eastus2
          
      - name: Restore PostgreSQL backup
        run: |
          az postgres flexible-server restore \
            --resource-group RBC-BackupTest \
            --name psql-rbc-test-restore \
            --source-server /subscriptions/{sub}/resourceGroups/RBCLeasingApp-Prod/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-rbc-prod \
            --restore-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S')
            
      - name: Validate restored database
        run: |
          # Test connection and run validation queries
          psql "host=psql-rbc-test-restore.postgres.database.azure.com dbname=leasing user=admin" \
            -c "SELECT COUNT(*) FROM information_schema.tables;"
            
      - name: Cleanup
        if: always()
        run: |
          az group delete --name RBC-BackupTest --yes --no-wait
```

## Key Vault Disaster Recovery

### Soft Delete & Purge Protection
```bicep
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: 'kv-rbc-${environmentName}'
  location: location
  properties: {
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableRbacAuthorization: true
    sku: {
      family: 'A'
      name: 'premium'
    }
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}
```

### Key Vault Backup Script
```powershell
# Backup all secrets to storage account
$vaultName = "kv-rbc-prod"
$storageAccount = "strbcbackupprod"
$container = "keyvault-backups"

# Get all secrets
$secrets = az keyvault secret list --vault-name $vaultName --query "[].name" -o tsv

foreach ($secret in $secrets) {
    # Backup each secret
    az keyvault secret backup `
        --vault-name $vaultName `
        --name $secret `
        --file "$secret.backup"
    
    # Upload to storage
    az storage blob upload `
        --account-name $storageAccount `
        --container-name $container `
        --file "$secret.backup" `
        --name "$(Get-Date -Format 'yyyy-MM-dd')/$secret.backup"
}
```

## Monitoring & Alerts for DR

### Availability Alerts
```bicep
resource availabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-availability-${environmentName}'
  location: 'global'
  properties: {
    severity: 0  // Critical
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ServiceUnavailable'
          metricNamespace: 'Microsoft.Web/sites'
          metricName: 'Http5xx'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Count'
        }
      ]
    }
    autoMitigate: false
    actions: [
      {
        actionGroupId: criticalActionGroup.id
      }
    ]
  }
}
```

## Recovery Testing Schedule

| Component | Test Frequency | Test Type | Duration |
|-----------|---------------|-----------|----------|
| PostgreSQL Backup | Weekly | Restore validation | 1 hour |
| Zone Failover | Monthly | Forced failover | 30 mins |
| Full DR | Quarterly | Complete failover | 4 hours |
| Key Vault | Monthly | Backup/restore | 30 mins |
| AKS Backup | Weekly | Velero backup test | 1 hour |

## Best Practices
1. Document all DR procedures clearly
2. Test recovery procedures regularly
3. Maintain up-to-date runbooks
4. Monitor backup success rates
5. Implement automated failover where possible
6. Keep secondary regions warm
7. Use Infrastructure as Code for consistency
8. Regular DR drills with the team
9. Monitor and alert on RPO/RTO violations
10. Maintain offline copies of critical documentation