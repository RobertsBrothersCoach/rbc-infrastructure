@description('Environment name')
@allowed(['dev', 'qa', 'prod'])
param environmentName string

@description('Location for resources')
param location string = resourceGroup().location

@description('Tags for resources')
param tags object = {}

@description('Log retention in days (2555 for 7 years PII compliance)')
param retentionInDays int = environmentName == 'prod' ? 2555 : 30

@description('Enable PII audit logging')
param enablePiiAuditLogging bool = true

@description('Daily quota in GB for Application Insights')
param dailyQuotaGb int = environmentName == 'prod' ? 100 : 10

@description('Alert email address')
param alertEmailAddress string = 'devops@tourbus-leasing.com'

@description('Enable SMS alerts for production')
param enableSmsAlerts bool = environmentName == 'prod'

@description('SMS phone number for alerts')
param smsPhoneNumber string = ''

// Log Analytics Workspace with enhanced configuration
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-rbcleasing-${environmentName}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableDataExport: true
      immediatePurgeDataOn30Days: environmentName != 'prod'
      disableLocalAuth: false
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: environmentName == 'prod' ? -1 : 5 // No cap for production
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights with enhanced settings
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-rbcleasing-${environmentName}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    RetentionInDays: environmentName == 'prod' ? 90 : 30
    ImmediatePurgeDataOn30Days: environmentName != 'prod'
    DisableLocalAuth: false
  }
}

// PII Audit Log Storage Account (7-year retention)
resource auditStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = if (enablePiiAuditLogging) {
  name: 'staudit${uniqueString(resourceGroup().id)}${environmentName}'
  location: location
  tags: tags
  sku: {
    name: environmentName == 'prod' ? 'Standard_GRS' : 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Cool' // Cost-effective for audit logs
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Blob service for storage account
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = if (enablePiiAuditLogging) {
  parent: auditStorageAccount
  name: 'default'
}

// Blob container for PII audit logs
resource auditContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = if (enablePiiAuditLogging) {
  parent: blobService
  name: 'pii-audit-logs'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'PII Access Audit Logs'
      retention: '7 years'
    }
  }
}

// Lifecycle management for 7-year retention
resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = if (enablePiiAuditLogging) {
  parent: auditStorageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'DeleteAfter7Years'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['pii-audit-logs/']
            }
            actions: {
              baseBlob: {
                delete: {
                  daysAfterModificationGreaterThan: 2555 // 7 years
                }
              }
            }
          }
        }
        {
          name: 'MoveToArchiveAfter90Days'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['pii-audit-logs/']
            }
            actions: {
              baseBlob: {
                tierToArchive: {
                  daysAfterModificationGreaterThan: 90
                }
              }
            }
          }
        }
      ]
    }
  }
}

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-rbcleasing-${environmentName}'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'TB${toUpper(environmentName)}'
    enabled: true
    emailReceivers: [
      {
        name: 'DevOpsTeam'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: enableSmsAlerts && !empty(smsPhoneNumber) ? [
      {
        name: 'OnCallEngineer'
        countryCode: '1'
        phoneNumber: smsPhoneNumber
      }
    ] : []
    azureAppPushReceivers: environmentName == 'prod' ? [
      {
        name: 'MobileApp'
        emailAddress: alertEmailAddress
      }
    ] : []
  }
}

// Alert Rule - High Error Rate
resource highErrorRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-high-error-rate-${environmentName}'
  location: 'global'
  tags: tags
  properties: {
    severity: environmentName == 'prod' ? 1 : 2
    enabled: true
    scopes: [
      applicationInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighErrorRate'
          metricName: 'exceptions/count'
          metricNamespace: 'microsoft.insights/components'
          operator: 'GreaterThan'
          threshold: environmentName == 'prod' ? 10 : 50
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Alert Rule - High Response Time
resource highResponseTimeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-high-response-time-${environmentName}'
  location: 'global'
  tags: tags
  properties: {
    severity: 2
    enabled: true
    scopes: [
      applicationInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighResponseTime'
          metricName: 'requests/duration'
          metricNamespace: 'microsoft.insights/components'
          operator: 'GreaterThan'
          threshold: environmentName == 'prod' ? 2000 : 5000 // milliseconds
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Alert Rule - Low Availability
resource lowAvailabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-low-availability-${environmentName}'
  location: 'global'
  tags: tags
  properties: {
    severity: 1
    enabled: true
    scopes: [
      applicationInsights.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'LowAvailability'
          metricName: 'availabilityResults/availabilityPercentage'
          metricNamespace: 'microsoft.insights/components'
          operator: 'LessThan'
          threshold: environmentName == 'prod' ? 99 : 95
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: false // Manual intervention required
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Outputs for other modules
output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
output applicationInsightsId string = applicationInsights.id
output applicationInsightsName string = applicationInsights.name
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output actionGroupId string = actionGroup.id
output auditStorageAccountName string = enablePiiAuditLogging ? auditStorageAccount.name : ''
output auditStorageAccountId string = enablePiiAuditLogging ? auditStorageAccount.id : ''