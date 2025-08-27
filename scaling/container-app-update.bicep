// Helper module to update Container App configuration
// Used by the scaling configuration module

@description('Container App name')
param containerAppName string

@description('Location')
param location string

@description('Container App Environment ID')
param environmentId string

@description('Configuration object')
param configuration object

@description('Template object with scaling rules')
param template object

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  properties: {
    environmentId: environmentId
    configuration: configuration
    template: template
  }
}

output containerAppId string = containerApp.id
output fqdn string = containerApp.properties.configuration.ingress.fqdn