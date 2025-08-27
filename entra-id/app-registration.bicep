// Azure Entra ID Application Registration Configuration
// This template configures the application registration for authentication

@description('Environment name')
@allowed(['dev', 'qa', 'prod'])
param environmentName string

@description('Application display name')
param appDisplayName string = 'Tour Bus Leasing Management ${environmentName}'

@description('Tenant ID for the Azure AD tenant')
param tenantId string

@description('Key Vault name for storing secrets')
param keyVaultName string

@description('Redirect URIs for the application')
param redirectUris array = environmentName == 'dev' ? [
  'http://localhost:3000/auth/callback'
  'http://localhost:5173/auth/callback'
] : environmentName == 'qa' ? [
  'https://qa-tourbus.azurewebsites.net/auth/callback'
  'https://qa-tourbus.azurecontainerapps.io/auth/callback'
] : [
  'https://tourbus.azurewebsites.net/auth/callback'
  'https://tourbus.azurecontainerapps.io/auth/callback'
  'https://www.tourbus-leasing.com/auth/callback'
]

@description('Tags for resources')
param tags object = {
  Environment: environmentName
  Application: 'TourBusLeasing'
  ManagedBy: 'Infrastructure'
}

// Note: Bicep doesn't directly support creating Entra ID app registrations
// This file documents the configuration that should be applied via Azure CLI or PowerShell

var appConfiguration = {
  displayName: appDisplayName
  signInAudience: 'AzureADMyOrg' // Single tenant
  web: {
    redirectUris: redirectUris
    implicitGrantSettings: {
      enableIdTokenIssuance: true
      enableAccessTokenIssuance: false
    }
  }
  requiredResourceAccess: [
    {
      // Microsoft Graph API
      resourceAppId: '00000003-0000-0000-c000-000000000000'
      resourceAccess: [
        {
          // User.Read
          id: 'e1fe6dd8-ba31-4d61-89e7-88639da4683d'
          type: 'Scope'
        }
        {
          // GroupMember.Read.All
          id: '98830695-27a2-44f7-8c18-0c3ebc9698f6'
          type: 'Scope'
        }
        {
          // openid
          id: '37f7f235-527c-4136-accd-4a02d197296e'
          type: 'Scope'
        }
        {
          // profile
          id: '14dad69e-099b-42c9-810b-d002981feec1'
          type: 'Scope'
        }
        {
          // email
          id: '64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0'
          type: 'Scope'
        }
      ]
    }
  ]
  passwordCredentials: []
  keyCredentials: []
  identifierUris: [
    'api://tourbus-${environmentName}'
  ]
  appRoles: [
    {
      allowedMemberTypes: ['User']
      description: 'Full system access and administrative privileges'
      displayName: 'Administrator'
      id: newGuid()
      isEnabled: true
      value: 'Administrator'
    }
    {
      allowedMemberTypes: ['User']
      description: 'Management level access to all modules'
      displayName: 'Manager'
      id: newGuid()
      isEnabled: true
      value: 'Manager'
    }
    {
      allowedMemberTypes: ['User']
      description: 'Access to CRM module for client management'
      displayName: 'CRM User'
      id: newGuid()
      isEnabled: true
      value: 'CRMUser'
    }
    {
      allowedMemberTypes: ['User']
      description: 'Access to fleet management and maintenance modules'
      displayName: 'Fleet Manager'
      id: newGuid()
      isEnabled: true
      value: 'FleetManager'
    }
    {
      allowedMemberTypes: ['User']
      description: 'Access to financial and reporting modules'
      displayName: 'Finance User'
      id: newGuid()
      isEnabled: true
      value: 'FinanceUser'
    }
    {
      allowedMemberTypes: ['User']
      description: 'Read-only access to all modules'
      displayName: 'Read Only User'
      id: newGuid()
      isEnabled: true
      value: 'ReadOnlyUser'
    }
  ]
  oauth2AllowIdTokenImplicitFlow: true
  oauth2AllowImplicitFlow: false
  publicClient: {
    redirectUris: []
  }
  spa: {
    redirectUris: environmentName == 'dev' ? [
      'http://localhost:3000'
      'http://localhost:5173'
    ] : []
  }
}

// Output the configuration for use in scripts
output appRegistrationConfig object = appConfiguration
output tenantId string = tenantId
output keyVaultName string = keyVaultName
output environment string = environmentName