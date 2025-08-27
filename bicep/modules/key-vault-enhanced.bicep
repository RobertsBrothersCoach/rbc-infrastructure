@description('Environment name')
param environmentName string

@description('Location for resources')
param location string

@description('Principal IDs that need access to Key Vault')
param principalIds array = []

@description('Log Analytics Workspace ID for diagnostics')
param logAnalyticsWorkspaceId string = ''

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-rbc-${environmentName}'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: environmentName == 'prod' ? 'premium' : 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: environmentName == 'prod' ? 90 : 7
    enableRbacAuthorization: true
    enablePurgeProtection: true // Once enabled, cannot be disabled
    publicNetworkAccess: environmentName == 'prod' ? 'Disabled' : 'Enabled'
    networkAcls: {
      defaultAction: environmentName == 'prod' ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
      ipRules: environmentName == 'prod' ? [] : [
        {
          value: '0.0.0.0/0' // Allow all IPs for dev/test only
        }
      ]
      virtualNetworkRules: []
    }
  }
}

// Role Definitions
var keyVaultSecretsUserRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var keyVaultSecretsOfficerRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
var keyVaultAdministratorRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')

// Assign Key Vault Secrets User role to service principals
resource keyVaultSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principalId in principalIds: if (!empty(principalId)) {
  scope: keyVault
  name: guid(keyVault.id, principalId, 'SecretsUser')
  properties: {
    principalId: principalId
    roleDefinitionId: keyVaultSecretsUserRole
    principalType: 'ServicePrincipal'
  }
}]

// PostgreSQL Connection String Secret
resource postgresqlConnectionString 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgresql-connection-string'
  properties: {
    attributes: {
      enabled: true
      exp: environmentName == 'prod' ? dateTimeToEpoch(dateTimeAdd(utcNow(), 'P90D')) : dateTimeToEpoch(dateTimeAdd(utcNow(), 'P180D'))
    }
    contentType: 'text/plain'
    value: 'To be updated by deployment'
  }
}

// PostgreSQL Admin Password Secret
resource postgresqlAdminPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgresql-admin-password'
  properties: {
    attributes: {
      enabled: true
      exp: environmentName == 'prod' ? dateTimeToEpoch(dateTimeAdd(utcNow(), 'P90D')) : dateTimeToEpoch(dateTimeAdd(utcNow(), 'P180D'))
    }
    contentType: 'text/plain'
    value: 'To be updated by deployment'
  }
}

// PostgreSQL Server Name Secret
resource postgresqlServerName 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgresql-server-name'
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
    value: 'rbc-db-${environmentName}.postgres.database.azure.com'
  }
}

// PostgreSQL Username Secret
resource postgresqlUsername 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgresql-username'
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
    value: 'rbcadmin'
  }
}

// PostgreSQL Database Name Secret
resource postgresqlDatabase 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgresql-database'
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
    value: 'rbc_leasing'
  }
}

// Redis Connection String Secret
resource redisConnectionString 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-connection-string'
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
    value: 'To be updated by deployment'
  }
}

// Redis Host Secret
resource redisHost 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-host'
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
    value: 'redis-rbc-${environmentName}.redis.cache.windows.net'
  }
}

// Redis Port Secret
resource redisPort 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-port'
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
    value: '6380'
  }
}

// Redis Primary Key Secret
resource redisPrimaryKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-primary-key'
  properties: {
    attributes: {
      enabled: true
      exp: dateTimeToEpoch(dateTimeAdd(utcNow(), 'P365D'))
    }
    contentType: 'text/plain'
    value: 'To be updated by deployment'
  }
}

// JWT Signing Key Secret
resource jwtSigningKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'jwt-signing-key'
  properties: {
    attributes: {
      enabled: true
      exp: dateTimeToEpoch(dateTimeAdd(utcNow(), 'P365D'))
    }
    contentType: 'text/plain'
    value: base64(newGuid())
  }
}

// API Key for internal services
resource apiKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'api-key'
  properties: {
    attributes: {
      enabled: true
      exp: dateTimeToEpoch(dateTimeAdd(utcNow(), 'P365D'))
    }
    contentType: 'text/plain'
    value: base64(newGuid())
  }
}

// Application Insights Connection String
resource appInsightsConnectionString 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'appinsights-connection-string'
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
    value: 'To be updated by deployment'
  }
}

// Storage Account Connection String (for backups, logs, etc.)
resource storageConnectionString 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-connection-string'
  properties: {
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
    value: 'To be updated by deployment'
  }
}

// Event Grid for secret expiration notifications
resource eventGridTopic 'Microsoft.EventGrid/systemTopics@2023-12-15-preview' = {
  name: 'eg-keyvault-${environmentName}'
  location: location
  properties: {
    source: keyVault.id
    topicType: 'Microsoft.KeyVault.vaults'
  }
}

// Diagnostic settings for audit logging
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  scope: keyVault
  name: 'keyvault-audit-logs'
  properties: {
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
        // Retention policies are no longer supported in diagnostic settings
      }
      {
        category: 'AzurePolicyEvaluationDetails'
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
    workspaceId: logAnalyticsWorkspaceId
  }
}

// Alert for secret expiration
resource secretExpirationAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (environmentName == 'prod') {
  name: 'alert-keyvault-secret-expiration-${environmentName}'
  location: 'global'
  properties: {
    severity: 2
    enabled: true
    scopes: [
      keyVault.id
    ]
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'SecretNearExpiry'
          metricName: 'ServiceApiLatency'
          metricNamespace: 'Microsoft.KeyVault/vaults'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: false
    targetResourceType: 'Microsoft.KeyVault/vaults'
    targetResourceRegion: location
    actions: []
  }
}

// Private Endpoint for Key Vault (production only)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = if (environmentName == 'prod') {
  name: 'pe-keyvault-${environmentName}'
  location: location
  properties: {
    subnet: {
      id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/RBCLeasingApp-${toUpper(take(environmentName, 1))}${toLower(skip(environmentName, 1))}/providers/Microsoft.Network/virtualNetworks/vnet-rbc-${environmentName}/subnets/snet-private-endpoints'
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-keyvault-${environmentName}'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

// Output
output name string = keyVault.name
output uri string = keyVault.properties.vaultUri
output id string = keyVault.id
output eventGridTopicId string = eventGridTopic.id