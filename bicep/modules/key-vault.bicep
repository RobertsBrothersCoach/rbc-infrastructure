@description('Environment name')
param environmentName string

@description('Location for resources')
param location string

@description('Principal IDs that need access to Key Vault')
param principalIds array = []

@description('Log Analytics Workspace ID for diagnostic settings')
param logAnalyticsWorkspaceId string = ''

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-rbc-${environmentName}'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: true
    enabledForDiskEncryption: false
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

// Assign Key Vault Secrets Officer role to service principals
resource keyVaultSecretsOfficerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principalId in principalIds: {
  scope: keyVault
  name: guid(keyVault.id, principalId, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalType: 'ServicePrincipal'
  }
}]

// Note: Secrets will be created by the modules that need them (PostgreSQL, etc.)
// These are commented out as they need actual values to be created
// The secretRotationPolicy property is not supported in the current API version
/*
resource postgresPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgresql-admin-password'
  properties: {
    value: 'will-be-set-by-postgresql-module'
    attributes: {
      enabled: true
    }
  }
}

resource jwtSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'jwt-signing-key'
  properties: {
    value: 'will-be-set-by-app-service-module'
    attributes: {
      enabled: true
    }
  }
}
*/

// Event Grid for secret rotation notifications
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
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    workspaceId: logAnalyticsWorkspaceId
  }
}

// Output
output name string = keyVault.name
output uri string = keyVault.properties.vaultUri
output id string = keyVault.id