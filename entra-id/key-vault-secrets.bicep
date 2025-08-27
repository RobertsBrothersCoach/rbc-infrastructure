// Key Vault configuration for storing Entra ID credentials
// This module creates secrets in Key Vault for the application credentials

@description('Key Vault name')
param keyVaultName string

@description('Environment name')
@allowed(['dev', 'qa', 'prod'])
param environmentName string

@description('Application ID from Entra ID')
@secure()
param applicationId string

@description('Client Secret from Entra ID')
@secure()
param clientSecret string

@description('Tenant ID')
@secure()
param tenantId string

@description('Secret expiration date')
param secretExpirationDate string = dateTimeAdd(utcNow(), 'P2Y') // 2 years from now

@description('Tags for resources')
param tags object = {
  Environment: environmentName
  Application: 'TourBusLeasing'
  ManagedBy: 'Infrastructure'
  Purpose: 'Authentication'
}

// Reference existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Store Application ID
resource applicationIdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'EntraId-ApplicationId'
  tags: union(tags, {
    Type: 'ApplicationId'
  })
  properties: {
    value: applicationId
    contentType: 'text/plain'
    attributes: {
      enabled: true
      exp: dateTimeToEpoch(secretExpirationDate)
    }
  }
}

// Store Client Secret
resource clientSecretSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'EntraId-ClientSecret'
  tags: union(tags, {
    Type: 'ClientSecret'
    ExpiresOn: secretExpirationDate
  })
  properties: {
    value: clientSecret
    contentType: 'text/plain'
    attributes: {
      enabled: true
      exp: dateTimeToEpoch(secretExpirationDate)
    }
  }
}

// Store Tenant ID
resource tenantIdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'EntraId-TenantId'
  tags: union(tags, {
    Type: 'TenantId'
  })
  properties: {
    value: tenantId
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Store Authority URL
resource authoritySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'EntraId-Authority'
  tags: union(tags, {
    Type: 'AuthorityUrl'
  })
  properties: {
    value: 'https://login.microsoftonline.com/${tenantId}'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Store Redirect URI
resource redirectUriSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'EntraId-RedirectUri'
  tags: union(tags, {
    Type: 'RedirectUri'
  })
  properties: {
    value: environmentName == 'dev' 
      ? 'http://localhost:3000/auth/callback'
      : environmentName == 'qa'
        ? 'https://qa-tourbus.azurecontainerapps.io/auth/callback'
        : 'https://tourbus.azurecontainerapps.io/auth/callback'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Store API Scope
resource apiScopeSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'EntraId-ApiScope'
  tags: union(tags, {
    Type: 'ApiScope'
  })
  properties: {
    value: 'api://tourbus-${environmentName}/.default'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Output secret URIs for reference
output applicationIdSecretUri string = applicationIdSecret.properties.secretUri
output clientSecretSecretUri string = clientSecretSecret.properties.secretUri
output tenantIdSecretUri string = tenantIdSecret.properties.secretUri
output authoritySecretUri string = authoritySecret.properties.secretUri
output redirectUriSecretUri string = redirectUriSecret.properties.secretUri
output apiScopeSecretUri string = apiScopeSecret.properties.secretUri

// Output secret identifiers for managed identity access
output applicationIdSecretId string = applicationIdSecret.id
output clientSecretSecretId string = clientSecretSecret.id
output tenantIdSecretId string = tenantIdSecret.id