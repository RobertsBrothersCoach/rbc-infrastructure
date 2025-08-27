// Container Apps Auto-Scaling Configuration
// Configures HTTP-based scaling with environment-specific rules

@description('Environment name (dev, qa, prod)')
@allowed(['dev', 'qa', 'prod'])
param environmentName string

@description('Container App name')
param containerAppName string

@description('Resource group name')
param resourceGroupName string = resourceGroup().name

// Environment-specific scaling configurations
var scalingConfigs = {
  dev: {
    minReplicas: 0
    maxReplicas: 2
    rules: [
      {
        name: 'http-scaling'
        http: {
          metadata: {
            concurrentRequests: '30'
          }
        }
      }
    ]
    scaleDownDelay: 600 // 10 minutes
  }
  qa: {
    minReplicas: 0
    maxReplicas: 3
    rules: [
      {
        name: 'http-scaling'
        http: {
          metadata: {
            concurrentRequests: '30'
          }
        }
      }
    ]
    scaleDownDelay: 600 // 10 minutes
  }
  prod: {
    minReplicas: 1
    maxReplicas: 10
    rules: [
      {
        name: 'http-scaling'
        http: {
          metadata: {
            concurrentRequests: '30'
          }
        }
      }
      {
        name: 'cpu-scaling'
        custom: {
          type: 'cpu'
          metadata: {
            type: 'Utilization'
            value: '70'
          }
        }
      }
      {
        name: 'memory-scaling'
        custom: {
          type: 'memory'
          metadata: {
            type: 'Utilization'
            value: '70'
          }
        }
      }
    ]
    scaleDownDelay: 600 // 10 minutes
  }
}

// Get the current scaling configuration
var currentConfig = scalingConfigs[environmentName]

// Reference to existing Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' existing = {
  name: containerAppName
}

// Module to update Container App scaling configuration
module updateScaling 'container-app-update.bicep' = {
  name: 'update-${containerAppName}-scaling'
  params: {
    containerAppName: containerApp.name
    location: containerApp.location
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: containerApp.properties.configuration.ingress
      registries: containerApp.properties.configuration.registries
      secrets: containerApp.properties.configuration.secrets
      dapr: containerApp.properties.configuration.dapr
    }
    template: {
      containers: containerApp.properties.template.containers
      scale: {
        minReplicas: currentConfig.minReplicas
        maxReplicas: currentConfig.maxReplicas
        rules: currentConfig.rules
      }
      volumes: containerApp.properties.template.volumes
      revisionSuffix: 'scaling-${uniqueString(utcNow())}'
    }
    environmentId: containerApp.properties.environmentId
  }
}

// Output the scaling configuration
output scalingConfiguration object = {
  environment: environmentName
  minReplicas: currentConfig.minReplicas
  maxReplicas: currentConfig.maxReplicas
  rules: currentConfig.rules
  scaleDownDelay: currentConfig.scaleDownDelay
}

output containerAppId string = containerApp.id
output containerAppName string = containerApp.name