@description('Environment name')
@allowed(['dev', 'qa', 'prod'])
param environmentName string

@description('Location for resources')
param location string = resourceGroup().location

@description('Secondary location for geo-replication')
param secondaryLocation string = 'westus2'

@description('Tags for resources')
param tags object = {}

@description('Enable geo-replication (Premium SKU required)')
param enableGeoReplication bool = environmentName == 'prod'

@description('Enable vulnerability scanning')
param enableVulnerabilityScanning bool = true

@description('Enable content trust')
param enableContentTrust bool = environmentName == 'prod'

@description('Days to retain untagged manifests')
param retentionDays int = environmentName == 'prod' ? 90 : 30

@description('Principal IDs that need pull access')
param pullPrincipalIds array = []

@description('Principal IDs that need push access')
param pushPrincipalIds array = []

// Variables
// Use fixed name 'acrtourbus' to match GitHub Actions workflow expectations
var acrName = 'acrtourbus'
var skuName = environmentName == 'prod' ? 'Premium' : 'Basic'

// Azure Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    adminUserEnabled: false // Disable admin user for security
    publicNetworkAccess: environmentName == 'prod' ? 'Disabled' : 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    policies: {
      quarantinePolicy: {
        status: enableVulnerabilityScanning ? 'enabled' : 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: enableContentTrust ? 'enabled' : 'disabled'
      }
      retentionPolicy: {
        days: retentionDays
        status: 'enabled'
      }
      exportPolicy: {
        status: environmentName == 'prod' ? 'disabled' : 'enabled'
      }
    }
    encryption: environmentName == 'prod' ? {
      status: 'enabled'
    } : {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    anonymousPullEnabled: false
  }
}

// Geo-replication for production
resource replication 'Microsoft.ContainerRegistry/registries/replications@2023-07-01' = if (enableGeoReplication && skuName == 'Premium') {
  parent: containerRegistry
  name: '${secondaryLocation}replica'
  location: secondaryLocation
  tags: tags
  properties: {
    regionEndpointEnabled: true
  }
}

// Retention policy for untagged manifests
resource retentionPolicy 'Microsoft.ContainerRegistry/registries/tasks@2019-04-01' = {
  parent: containerRegistry
  name: 'purgeUntaggedManifests'
  location: location
  properties: {
    platform: {
      os: 'Linux'
      architecture: 'amd64'
    }
    agentConfiguration: {
      cpu: 2
    }
    step: {
      type: 'EncodedTask'
      encodedTaskContent: base64('''
        version: v1.1.0
        steps:
          - cmd: acr purge --filter "tourbus-frontend:.*" --filter "tourbus-backend:.*" --untagged --ago ${retentionDays}d
            disableWorkingDirectoryOverride: true
            timeout: 3600
      ''')
    }
    trigger: {
      timerTriggers: [
        {
          schedule: '0 2 * * *' // Run daily at 2 AM
          name: 'dailyPurge'
        }
      ]
    }
    timeout: 3600
  }
}

// Vulnerability scanning webhook
resource vulnerabilityScanWebhook 'Microsoft.ContainerRegistry/registries/webhooks@2023-07-01' = if (enableVulnerabilityScanning) {
  parent: containerRegistry
  name: 'vulnerabilityscan'
  location: location
  properties: {
    status: 'enabled'
    scope: '*'
    actions: [
      'push'
      'quarantine'
    ]
    serviceUri: 'https://tourbus-security.azurewebsites.net/api/scan'
  }
}

// Build webhook for CI/CD
resource buildWebhook 'Microsoft.ContainerRegistry/registries/webhooks@2023-07-01' = {
  parent: containerRegistry
  name: 'cicdwebhook'
  location: location
  properties: {
    status: 'enabled'
    scope: '*'
    actions: [
      'push'
    ]
    serviceUri: 'https://tourbus-deploy.azurewebsites.net/api/deploy'
  }
}

// Role assignments for pull access
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principalId in pullPrincipalIds: {
  scope: containerRegistry
  name: guid(containerRegistry.id, principalId, '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalType: 'ServicePrincipal'
  }
}]

// Role assignments for push access
resource acrPushRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principalId in pushPrincipalIds: {
  scope: containerRegistry
  name: guid(containerRegistry.id, principalId, '8311e382-0749-4cb8-b61a-304f252e45ec')
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec') // AcrPush
    principalType: 'ServicePrincipal'
  }
}]

// Diagnostic settings
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: containerRegistry
  name: 'acr-diagnostics'
  properties: {
    workspaceId: resourceId('Microsoft.OperationalInsights/workspaces', 'log-tourbus-${environmentName}')
    logs: [
      {
        category: 'ContainerRegistryRepositoryEvents'
        enabled: true
        // Retention policies are no longer supported in diagnostic settings
      }
      {
        category: 'ContainerRegistryLoginEvents'
        enabled: true
        // Retention policies are no longer supported in diagnostic settings
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        // Retention policies are no longer supported in diagnostic settings
      }
    ]
  }
}

// Outputs
output registryName string = containerRegistry.name
output registryLoginServer string = containerRegistry.properties.loginServer
output registryId string = containerRegistry.id