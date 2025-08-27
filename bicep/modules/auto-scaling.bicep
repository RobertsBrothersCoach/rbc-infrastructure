@description('Environment name')
@allowed(['dev', 'qa', 'prod'])
param environmentName string

@description('Location for resources')
param location string

@description('App Service Plan name to configure auto-scaling for')
param appServicePlanName string

@description('Container Apps Environment name to configure auto-scaling for')
param containerAppsEnvironmentName string = ''

@description('Application Insights resource ID for monitoring')
param applicationInsightsId string

@description('PostgreSQL Server name to configure auto-scaling for')
param postgresqlServerName string = ''

@description('Redis Cache name to configure auto-scaling for')
param redisCacheName string = ''

// Auto-scaling configurations per environment
var scalingProfiles = {
  dev: {
    minInstances: 0
    maxInstances: 2
    defaultInstances: 1
    cpuThresholdHigh: 80
    cpuThresholdLow: 30
    memoryThresholdHigh: 80
    memoryThresholdLow: 40
    httpQueueThreshold: 10
    scaleOutCooldown: 'PT5M'
    scaleInCooldown: 'PT10M'
    enableScheduledScaling: false
  }
  qa: {
    minInstances: 1
    maxInstances: 3
    defaultInstances: 1
    cpuThresholdHigh: 75
    cpuThresholdLow: 30
    memoryThresholdHigh: 75
    memoryThresholdLow: 35
    httpQueueThreshold: 15
    scaleOutCooldown: 'PT5M'
    scaleInCooldown: 'PT10M'
    enableScheduledScaling: true
  }
  prod: {
    minInstances: 2
    maxInstances: 10
    defaultInstances: 3
    cpuThresholdHigh: 70
    cpuThresholdLow: 25
    memoryThresholdHigh: 70
    memoryThresholdLow: 30
    httpQueueThreshold: 20
    scaleOutCooldown: 'PT3M'
    scaleInCooldown: 'PT5M'
    enableScheduledScaling: true
  }
}

var currentProfile = scalingProfiles[environmentName]

// App Service Auto-scale Settings
resource appServiceAutoScale 'Microsoft.Insights/autoscalesettings@2022-10-01' = if (!empty(appServicePlanName)) {
  name: 'autoscale-${appServicePlanName}'
  location: location
  properties: {
    enabled: true
    targetResourceUri: resourceId('Microsoft.Web/serverfarms', appServicePlanName)
    profiles: [
      // Default profile with metric-based scaling
      {
        name: 'Default scaling profile'
        capacity: {
          minimum: string(currentProfile.minInstances)
          maximum: string(currentProfile.maxInstances)
          default: string(currentProfile.defaultInstances)
        }
        rules: [
          // Scale out on high CPU
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricNamespace: 'microsoft.web/serverfarms'
              metricResourceUri: resourceId('Microsoft.Web/serverfarms', appServicePlanName)
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: currentProfile.cpuThresholdHigh
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: currentProfile.scaleOutCooldown
            }
          }
          // Scale in on low CPU
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricNamespace: 'microsoft.web/serverfarms'
              metricResourceUri: resourceId('Microsoft.Web/serverfarms', appServicePlanName)
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: currentProfile.cpuThresholdLow
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: currentProfile.scaleInCooldown
            }
          }
          // Scale out on high memory
          {
            metricTrigger: {
              metricName: 'MemoryPercentage'
              metricNamespace: 'microsoft.web/serverfarms'
              metricResourceUri: resourceId('Microsoft.Web/serverfarms', appServicePlanName)
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: currentProfile.memoryThresholdHigh
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: currentProfile.scaleOutCooldown
            }
          }
          // Scale in on low memory
          {
            metricTrigger: {
              metricName: 'MemoryPercentage'
              metricNamespace: 'microsoft.web/serverfarms'
              metricResourceUri: resourceId('Microsoft.Web/serverfarms', appServicePlanName)
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: currentProfile.memoryThresholdLow
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: currentProfile.scaleInCooldown
            }
          }
          // Scale out rapidly on HTTP queue length
          {
            metricTrigger: {
              metricName: 'HttpQueueLength'
              metricNamespace: 'microsoft.web/serverfarms'
              metricResourceUri: resourceId('Microsoft.Web/serverfarms', appServicePlanName)
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: currentProfile.httpQueueThreshold
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '2'
              cooldown: 'PT3M'
            }
          }
        ]
      }
      // Weekend scale-down profile (prod only)
      {
        name: 'Weekend scale-down'
        capacity: {
          minimum: string(environmentName == 'prod' ? 1 : 0)
          maximum: string(environmentName == 'prod' ? 3 : 1)
          default: string(environmentName == 'prod' ? 1 : 0)
        }
        rules: []
        recurrence: currentProfile.enableScheduledScaling ? {
          frequency: 'Week'
          schedule: {
            timeZone: 'Eastern Standard Time'
            days: ['Saturday', 'Sunday']
            hours: [0]
            minutes: [0]
          }
        } : null
      }
      // Night time scale-down profile
      {
        name: 'Night time scale-down'
        capacity: {
          minimum: string(environmentName == 'prod' ? 1 : 0)
          maximum: string(environmentName == 'prod' ? 2 : 1)
          default: string(environmentName == 'prod' ? 1 : 0)
        }
        rules: []
        recurrence: currentProfile.enableScheduledScaling ? {
          frequency: 'Day'
          schedule: {
            timeZone: 'Eastern Standard Time'
            days: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']
            hours: [20]
            minutes: [0]
          }
        } : null
      }
      // Business hours scale-up profile
      {
        name: 'Business hours scale-up'
        capacity: {
          minimum: string(currentProfile.minInstances)
          maximum: string(currentProfile.maxInstances)
          default: string(currentProfile.defaultInstances)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricNamespace: 'microsoft.web/serverfarms'
              metricResourceUri: resourceId('Microsoft.Web/serverfarms', appServicePlanName)
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: currentProfile.cpuThresholdHigh - 10
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT3M'
            }
          }
        ]
        recurrence: currentProfile.enableScheduledScaling ? {
          frequency: 'Day'
          schedule: {
            timeZone: 'Eastern Standard Time'
            days: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']
            hours: [7]
            minutes: [0]
          }
        } : null
      }
    ]
    notifications: [
      {
        operation: 'Scale'
        email: {
          sendToSubscriptionAdministrator: true
          sendToSubscriptionCoAdministrators: true
          customEmails: []
        }
        webhooks: []
      }
    ]
  }
}

// Metric alerts for scaling events
resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (!empty(appServicePlanName)) {
  name: '${appServicePlanName}-high-cpu-alert'
  location: 'global'
  properties: {
    description: 'Alert when CPU usage remains high after scaling'
    severity: 2
    enabled: true
    scopes: [
      resourceId('Microsoft.Web/serverfarms', appServicePlanName)
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCpuCondition'
          metricName: 'CpuPercentage'
          operator: 'GreaterThan'
          threshold: 90
          timeAggregation: 'Average'
        }
      ]
    }
    actions: []
  }
}

resource memoryAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (!empty(appServicePlanName)) {
  name: '${appServicePlanName}-high-memory-alert'
  location: 'global'
  properties: {
    description: 'Alert when memory usage remains high after scaling'
    severity: 2
    enabled: true
    scopes: [
      resourceId('Microsoft.Web/serverfarms', appServicePlanName)
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighMemoryCondition'
          metricName: 'MemoryPercentage'
          operator: 'GreaterThan'
          threshold: 85
          timeAggregation: 'Average'
        }
      ]
    }
    actions: []
  }
}

// Database connection pool alert
resource dbConnectionAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (!empty(postgresqlServerName)) {
  name: '${postgresqlServerName}-connection-limit-alert'
  location: 'global'
  properties: {
    description: 'Alert when database connections approach limit'
    severity: 1
    enabled: true
    scopes: [
      resourceId('Microsoft.DBforPostgreSQL/flexibleServers', postgresqlServerName)
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighConnectionCount'
          metricName: 'active_connections'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
        }
      ]
    }
    actions: []
  }
}

// Redis memory alert
resource redisMemoryAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (!empty(redisCacheName)) {
  name: '${redisCacheName}-memory-alert'
  location: 'global'
  properties: {
    description: 'Alert when Redis memory usage is high'
    severity: 2
    enabled: true
    scopes: [
      resourceId('Microsoft.Cache/redis', redisCacheName)
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighMemoryUsage'
          metricName: 'UsedMemoryPercentage'
          operator: 'GreaterThan'
          threshold: 75
          timeAggregation: 'Average'
        }
      ]
    }
    actions: []
  }
}

// Application performance alert
resource responseTimeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'app-high-response-time-alert'
  location: 'global'
  properties: {
    description: 'Alert when application response time is high'
    severity: 2
    enabled: true
    scopes: [
      applicationInsightsId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighResponseTime'
          metricName: 'requests/duration'
          operator: 'GreaterThan'
          threshold: 2000 // 2 seconds
          timeAggregation: 'Average'
        }
      ]
    }
    actions: []
  }
}

// Outputs
output autoScaleSettingsId string = appServiceAutoScale.id
output scalingConfiguration object = {
  environment: environmentName
  minInstances: currentProfile.minInstances
  maxInstances: currentProfile.maxInstances
  cpuThresholdHigh: currentProfile.cpuThresholdHigh
  memoryThresholdHigh: currentProfile.memoryThresholdHigh
  scaleOutCooldown: currentProfile.scaleOutCooldown
  scaleInCooldown: currentProfile.scaleInCooldown
}