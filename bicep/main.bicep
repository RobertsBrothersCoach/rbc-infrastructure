targetScope = 'subscription'

@description('Environment name')
@allowed(['dev', 'qa', 'prod'])
param environmentName string

@description('Azure region for resources - Primary region with availability zones')
@allowed(['eastus2', 'westcentralus', 'eastus'])
param location string = 'eastus2'

@description('Backup region for disaster recovery')
@allowed(['westcentralus', 'eastus2', 'westus2'])
param backupRegion string = 'westcentralus'

@description('Enable auto-shutdown for non-production')
param enableAutoShutdown bool = environmentName != 'prod'

@description('PostgreSQL administrator password')
@secure()
param administratorPassword string

// Resource Group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'RBCLeasingApp-${toUpper(take(environmentName, 1))}${toLower(skip(environmentName, 1))}'
  location: location
  tags: {
    Environment: environmentName
    Application: 'RBCLeasingApp'
    ManagedBy: 'Bicep'
    CostCenter: 'Operations'
  }
}

// Deploy network security first
module networkSecurity 'modules/network-security.bicep' = {
  scope: resourceGroup
  name: 'networkSecurity-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
  }
}

// Deploy monitoring early so it's available for diagnostic settings
module monitoring 'modules/monitoring-enhanced.bicep' = {
  scope: resourceGroup
  name: 'monitoring-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
    retentionInDays: environmentName == 'prod' ? 2555 : 30
    enablePiiAuditLogging: true
    dailyQuotaGb: environmentName == 'prod' ? 100 : 10
    alertEmailAddress: 'devops@tourbus-leasing.com'
    enableSmsAlerts: environmentName == 'prod'
    smsPhoneNumber: ''
    tags: {
      Environment: environmentName
      Application: 'RBCLeasingApp'
      ManagedBy: 'Bicep'
    }
  }
  dependsOn: [
    networkSecurity
  ]
}

// Deploy Key Vault after monitoring so we can use the workspace for diagnostics
module keyVault 'modules/key-vault.bicep' = {
  scope: resourceGroup
  name: 'keyVault-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
    principalIds: [] // Will be updated with service identities after creation
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
  dependsOn: [
    networkSecurity
    monitoring
  ]
}

// Deploy cost-effective AKS cluster for GitOps
module aksCluster 'modules/aks-cost-effective.bicep' = {
  scope: resourceGroup
  name: 'aksCluster-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
    keyVaultName: keyVault.outputs.name
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    enableAutoShutdown: enableAutoShutdown
  }
  dependsOn: [
    monitoring
    keyVault
  ]
}

module postgresql 'modules/postgresql.bicep' = {
  scope: resourceGroup
  name: 'postgresql-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
    enableHA: environmentName == 'prod'
    backupRegion: backupRegion
    keyVaultName: keyVault.outputs.name
    administratorPassword: administratorPassword
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

module redis 'modules/redis.bicep' = {
  scope: resourceGroup
  name: 'redis-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
    sku: environmentName == 'prod' ? 'Premium' : 'Basic'
    keyVaultName: keyVault.outputs.name
  }
}

// Front Door will be configured later via Kubernetes Ingress (nginx-ingress or similar)
// Monitoring module moved earlier in deployment sequence

// Container Registry for Docker images
module containerRegistry 'modules/container-registry.bicep' = {
  scope: resourceGroup
  name: 'containerRegistry-${environmentName}'
  params: {
    environmentName: environmentName
    location: location
    enableGeoReplication: environmentName == 'prod'
    enableVulnerabilityScanning: true
    enableContentTrust: environmentName == 'prod'
    retentionDays: environmentName == 'prod' ? 90 : 30
    pullPrincipalIds: [
      aksCluster.outputs.kubeletIdentityObjectId
    ]
    pushPrincipalIds: [] // GitHub Actions will use service principal authentication
    tags: {
      Environment: environmentName
      Application: 'RBCLeasingApp'
      ManagedBy: 'Bicep'
    }
  }
  dependsOn: [
    aksCluster
  ]
}

// Collect all service principal IDs
var servicePrincipalIds = [
  postgresql.outputs.principalId
  redis.outputs.principalId
  aksCluster.outputs.principalId
]

// Assign Key Vault access to all service principals
module roleAssignments 'modules/role-assignments.bicep' = {
  scope: resourceGroup
  name: 'roleAssignments-${environmentName}'
  params: {
    keyVaultId: keyVault.outputs.id
    principalIds: servicePrincipalIds
    environmentName: environmentName
  }
}

// Outputs
output resourceGroupName string = resourceGroup.name
output aksClusterName string = aksCluster.outputs.clusterName
output aksClusterFqdn string = aksCluster.outputs.clusterFqdn
output keyVaultName string = keyVault.outputs.name
output keyVaultUri string = keyVault.outputs.uri
output applicationInsightsConnectionString string = monitoring.outputs.applicationInsightsConnectionString
output applicationInsightsInstrumentationKey string = monitoring.outputs.applicationInsightsInstrumentationKey
output containerRegistryName string = containerRegistry.outputs.registryName
output containerRegistryLoginServer string = containerRegistry.outputs.registryLoginServer

// Secret URIs for application configuration
output postgresqlConnectionStringSecretUri string = postgresql.outputs.keyVaultSecretUri
output redisConnectionStringSecretUri string = redis.outputs.keyVaultSecretUri

// Cost optimization information
output estimatedMonthlyCost string = aksCluster.outputs.estimatedMonthlyCost
output costOptimizationFeatures array = aksCluster.outputs.costOptimizationFeatures