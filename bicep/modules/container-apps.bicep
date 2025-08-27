param environmentName string
param location string
param minReplicas int
param maxReplicas int
param keyVaultName string = ''
param logAnalyticsWorkspaceId string
param logAnalyticsWorkspaceName string
param applicationInsightsConnectionString string = ''

// Check if the region supports availability zones
var regionHasZones = contains(['eastus', 'eastus2', 'westus2'], location)

// Reference existing Log Analytics workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: 'cae-rbcleasing-${environmentName}'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    zoneRedundant: environmentName == 'prod' && regionHasZones
    daprAIConnectionString: !empty(applicationInsightsConnectionString) ? applicationInsightsConnectionString : null
  }
}

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-rbcleasing-frontend-${environmentName}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      // Registry will be configured after container registry is created
      registries: []
      secrets: !empty(keyVaultName) ? [
        {
          name: 'api-key'
          keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/api-key'
          identity: 'system'
        }
      ] : []
    }
    template: {
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-requests'
            http: {
              metadata: {
                concurrentRequests: '30'
              }
            }
          }
          {
            name: 'cpu-utilization'
            custom: {
              type: 'cpu'
              metadata: {
                type: 'Utilization'
                value: '70'
              }
            }
          }
        ]
      }
      containers: [
        {
          name: 'frontend'
          // TODO: Update to actual image once container registry and images are ready
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest' // Placeholder image
          resources: {
            cpu: json(environmentName == 'prod' ? '1.0' : '0.25')
            memory: environmentName == 'prod' ? '2Gi' : '0.5Gi'
          }
          env: [
            {
              name: 'ENVIRONMENT'
              value: environmentName
            }
            {
              name: 'API_URL'
              value: 'https://ca-rbcleasing-backend-${environmentName}.azurecontainerapps.io/api'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsightsConnectionString
            }
            {
              name: 'NODE_ENV'
              value: environmentName == 'prod' ? 'production' : 'development'
            }
          ]
        }
      ]
    }
  }
}

resource containerAppBackend 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-rbcleasing-backend-${environmentName}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 5000
        transport: 'auto'
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      // Registry will be configured after container registry is created
      registries: []
      secrets: !empty(keyVaultName) ? [
        {
          name: 'db-connection'
          keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/PostgreSQL-ConnectionString'
          identity: 'system'
        }
      ] : []
    }
    template: {
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-requests'
            http: {
              metadata: {
                concurrentRequests: '30'
              }
            }
          }
          {
            name: 'cpu-utilization'
            custom: {
              type: 'cpu'
              metadata: {
                type: 'Utilization'
                value: '70'
              }
            }
          }
        ]
      }
      containers: [
        {
          name: 'backend'
          // TODO: Update to actual image once container registry and images are ready
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest' // Placeholder image
          resources: {
            cpu: json(environmentName == 'prod' ? '1.0' : '0.5')
            memory: environmentName == 'prod' ? '2Gi' : '1Gi'
          }
          env: [
            {
              name: 'ENVIRONMENT'
              value: environmentName
            }
            {
              name: 'KEY_VAULT_NAME'
              value: keyVaultName
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsightsConnectionString
            }
            {
              name: 'NODE_ENV'
              value: environmentName == 'prod' ? 'production' : 'development'
            }
            {
              name: 'PORT'
              value: '5000'
            }
          ]
        }
      ]
    }
  }
}

output frontendUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output backendUrl string = 'https://${containerAppBackend.properties.configuration.ingress.fqdn}'
output fqdn string = containerApp.properties.configuration.ingress.fqdn
output backendFqdn string = containerAppBackend.properties.configuration.ingress.fqdn
output principalId string = containerApp.identity.principalId
output backendPrincipalId string = containerAppBackend.identity.principalId