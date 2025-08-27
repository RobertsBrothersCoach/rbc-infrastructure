@description('Environment name')
param environmentName string

@description('Location for resources')
param location string

@description('Redis SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param sku string = 'Basic'

@description('Key Vault name for storing secrets')
param keyVaultName string

// Determine SKU properties
var skuMap = {
  Basic: {
    name: 'Basic'
    family: 'C'
    capacity: 0
  }
  Standard: {
    name: 'Standard'
    family: 'C'
    capacity: 1
  }
  Premium: {
    name: 'Premium'
    family: 'P'
    capacity: 1
  }
}

// Zone configuration for Premium tier (zones only supported in Premium and in certain regions)
var regionHasZones = contains(['eastus', 'eastus2', 'westus2'], location)
var zones = (sku == 'Premium' && regionHasZones) ? ['1', '2', '3'] : []

// Reference existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Redis Cache
resource redis 'Microsoft.Cache/redis@2023-08-01' = {
  name: 'redis-rbcleasing-${environmentName}'
  location: location
  zones: zones
  properties: {
    sku: {
      name: skuMap[sku].name
      family: skuMap[sku].family
      capacity: skuMap[sku].capacity
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
      // Zonal configuration is controlled by zones property, not in redisConfiguration
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Store Redis primary key in Key Vault
resource redisPrimaryKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-primary-key'
  properties: {
    value: listKeys(redis.id, '2023-08-01').primaryKey
  }
}

// Store Redis connection string in Key Vault
resource redisConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-connection-string'
  properties: {
    value: '${redis.properties.hostName}:${redis.properties.sslPort},password=${listKeys(redis.id, '2023-08-01').primaryKey},ssl=True,abortConnect=False'
  }
}

// Store Redis host details separately
resource redisHostSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-host'
  properties: {
    value: redis.properties.hostName
  }
}

resource redisPortSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-port'
  properties: {
    value: string(redis.properties.sslPort)
  }
}

// Output only references to Key Vault secrets, not actual values
output hostName string = redis.properties.hostName
output port int = redis.properties.sslPort
output keyVaultSecretUri string = redisConnectionStringSecret.properties.secretUri
output principalId string = redis.identity.principalId