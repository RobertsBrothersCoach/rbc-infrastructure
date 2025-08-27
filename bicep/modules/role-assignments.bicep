@description('Key Vault resource ID')
param keyVaultId string

@description('Principal IDs that need Key Vault access')
param principalIds array

@description('Environment name')
param environmentName string

// Reference existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: split(keyVaultId, '/')[8]
}

// Key Vault Secrets User role definition ID
var keyVaultSecretsUserRoleDefinitionId = '4633458b-17de-408a-b874-0445c86b69e6'

// Assign Key Vault Secrets User role to all principals
resource keyVaultRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (principalId, i) in principalIds: {
  scope: keyVault
  name: guid(keyVault.id, principalId, keyVaultSecretsUserRoleDefinitionId)
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleDefinitionId)
    principalType: 'ServicePrincipal'
  }
}]

output assignmentCount int = length(principalIds)