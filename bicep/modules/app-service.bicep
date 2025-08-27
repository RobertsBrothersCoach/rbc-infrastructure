@description('Environment name')
param environmentName string

@description('Location for resources')
param location string

@description('Always on setting')
param alwaysOn bool = false

@description('App Service Plan SKU')
param sku string = 'B1'

@description('Enable zone redundancy for high availability')
param zoneRedundant bool = false

// Check if the region supports availability zones
var regionHasZones = contains(['eastus', 'eastus2', 'westus2'], location)
var effectiveZoneRedundant = zoneRedundant && regionHasZones

@description('Key Vault name for accessing secrets')
param keyVaultName string = ''

@description('PostgreSQL connection string secret URI')
param postgresqlSecretUri string = ''

@description('Redis connection string secret URI')
param redisSecretUri string = ''

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'asp-rbc-${environmentName}'
  location: location
  sku: {
    name: sku
    capacity: effectiveZoneRedundant ? 3 : 1
  }
  kind: 'linux'
  properties: {
    reserved: true
    zoneRedundant: effectiveZoneRedundant
  }
}

// App Service (Web App)
resource appService 'Microsoft.Web/sites@2023-01-01' = {
  name: 'rbc-api-${environmentName}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'NODE|18-lts'
      alwaysOn: alwaysOn
      appSettings: [
        {
          name: 'NODE_ENV'
          value: environmentName == 'prod' ? 'production' : 'development'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'DB_CONNECTION_STRING'
          value: !empty(postgresqlSecretUri) ? '@Microsoft.KeyVault(SecretUri=${postgresqlSecretUri})' : ''
        }
        {
          name: 'REDIS_URL'
          value: !empty(redisSecretUri) ? '@Microsoft.KeyVault(SecretUri=${redisSecretUri})' : ''
        }
        {
          name: 'JWT_SECRET'
          value: !empty(keyVaultName) ? '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=jwt-signing-key)' : ''
        }
        {
          name: 'KEY_VAULT_NAME'
          value: keyVaultName
        }
      ]
      cors: {
        allowedOrigins: [
          'http://localhost:5173'
          'https://rbc-frontend-${environmentName}.azurecontainerapps.io'
        ]
      }
    }
    httpsOnly: true
  }
}

// Grant App Service access to Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (!empty(keyVaultName)) {
  name: keyVaultName
}

resource keyVaultAccessPolicy 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(keyVaultName)) {
  scope: keyVault
  name: guid(appService.id, 'KeyVaultSecretsUser')
  properties: {
    principalId: appService.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalType: 'ServicePrincipal'
  }
}

// Output
output url string = 'https://${appService.properties.defaultHostName}'
output name string = appService.name
output principalId string = appService.identity.principalId