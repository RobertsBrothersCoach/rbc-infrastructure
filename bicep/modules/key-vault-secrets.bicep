@description('The name of the Key Vault')
param keyVaultName string

@description('Environment name')
param environmentName string

@description('PostgreSQL server name')
param postgresServerName string

@description('PostgreSQL admin username')
@secure()
param postgresAdminUsername string

@description('PostgreSQL admin password')
@secure()
param postgresAdminPassword string

@description('Redis cache name')
param redisCacheName string

@description('Redis primary key')
@secure()
param redisPrimaryKey string

@description('Storage account name')
param storageAccountName string

@description('Storage account key')
@secure()
param storageAccountKey string

@description('JWT Secret')
@secure()
param jwtSecret string = newGuid()

@description('JWT Refresh Secret')
@secure()
param jwtRefreshSecret string = newGuid()

@description('SendGrid API Key')
@secure()
param sendGridApiKey string = ''

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Location for resources')
param location string = resourceGroup().location

// Reference existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Database Secrets
resource dbHostSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'db-host'
  properties: {
    value: '${postgresServerName}.postgres.database.azure.com'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource dbPortSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'db-port'
  properties: {
    value: '5432'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource dbUserSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'db-user'
  properties: {
    value: postgresAdminUsername
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource dbPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'db-password'
  properties: {
    value: postgresAdminPassword
    contentType: 'text/plain'
    attributes: {
      enabled: true
      expiryTime: dateTimeAdd(utcNow(), 'P90D') // 90 days rotation
    }
  }
}

resource dbNameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'db-name'
  properties: {
    value: 'tourbus_${environmentName}'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// JWT Secrets
resource jwtSecretResource 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'jwt-secret'
  properties: {
    value: jwtSecret
    contentType: 'text/plain'
    attributes: {
      enabled: true
      expiryTime: dateTimeAdd(utcNow(), 'P180D') // 180 days rotation
    }
  }
}

resource jwtRefreshSecretResource 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'jwt-refresh-secret'
  properties: {
    value: jwtRefreshSecret
    contentType: 'text/plain'
    attributes: {
      enabled: true
      expiryTime: dateTimeAdd(utcNow(), 'P180D') // 180 days rotation
    }
  }
}

// Redis Secrets
resource redisUrlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-url'
  properties: {
    value: 'rediss://:${redisPrimaryKey}@${redisCacheName}.redis.cache.windows.net:6380'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource redisPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-password'
  properties: {
    value: redisPrimaryKey
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Storage Secrets
resource storageConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-connection'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccountKey};EndpointSuffix=core.windows.net'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource storageContainerSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-container'
  properties: {
    value: 'uploads-${environmentName}'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Email Service Secrets
resource sendGridApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(sendGridApiKey)) {
  parent: keyVault
  name: 'sendgrid-api-key'
  properties: {
    value: sendGridApiKey
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource emailFromSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'email-from'
  properties: {
    value: 'noreply@tourbus-leasing.com'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Application Insights Secret
resource appInsightsSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'appinsights-connection'
  properties: {
    value: appInsightsConnectionString
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Outputs
output keyVaultUri string = keyVault.properties.vaultUri
output secretCount int = 14