@description('Environment name')
param environmentName string

@description('Location for resources')
param location string

// Virtual Network for secure networking
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-rbc-${environmentName}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-app-services'
        properties: {
          addressPrefix: '10.0.1.0/24'
          serviceEndpoints: [
            {
              service: 'Microsoft.KeyVault'
            }
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.Sql'
            }
          ]
          delegations: [
            {
              name: 'delegation-app-services'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'snet-database'
        properties: {
          addressPrefix: '10.0.2.0/24'
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
          delegations: [
            {
              name: 'delegation-postgresql'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
      {
        name: 'snet-redis'
        properties: {
          addressPrefix: '10.0.3.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: '10.0.4.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-container-apps'
        properties: {
          addressPrefix: '10.0.5.0/24'
          delegations: [
            {
              name: 'delegation-container-apps'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ]
  }
}

// Network Security Group for App Services
resource nsgAppServices 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-app-services-${environmentName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHTTPS'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowHTTP'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: environmentName == 'prod' ? 'Deny' : 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// Network Security Group for Database
resource nsgDatabase 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-database-${environmentName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowPostgreSQLFromAppServices'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5432'
          sourceAddressPrefix: '10.0.1.0/24'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowPostgreSQLFromContainerApps'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5432'
          sourceAddressPrefix: '10.0.5.0/24'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// Private DNS Zone for Key Vault
resource privateDnsZoneKeyVault 'Microsoft.Network/privateDnsZones@2020-06-01' = if (environmentName == 'prod') {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  properties: {}
}

// Private DNS Zone for PostgreSQL
resource privateDnsZonePostgreSQL 'Microsoft.Network/privateDnsZones@2020-06-01' = if (environmentName == 'prod') {
  name: 'privatelink.postgres.database.azure.com'
  location: 'global'
  properties: {}
}

// Private DNS Zone for Redis
resource privateDnsZoneRedis 'Microsoft.Network/privateDnsZones@2020-06-01' = if (environmentName == 'prod') {
  name: 'privatelink.redis.cache.windows.net'
  location: 'global'
  properties: {}
}

// Link VNet to Private DNS Zones
resource vnetLinkKeyVault 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (environmentName == 'prod') {
  parent: privateDnsZoneKeyVault
  name: '${vnet.name}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource vnetLinkPostgreSQL 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (environmentName == 'prod') {
  parent: privateDnsZonePostgreSQL
  name: '${vnet.name}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource vnetLinkRedis 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (environmentName == 'prod') {
  parent: privateDnsZoneRedis
  name: '${vnet.name}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// WAF Policy for production
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-09-01' = if (environmentName == 'prod') {
  name: 'waf-rbc-${environmentName}'
  location: location
  properties: {
    customRules: []
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 10
      state: 'Enabled'
      mode: 'Prevention'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
      ]
    }
  }
}

// DDoS Protection Plan for production
resource ddosProtectionPlan 'Microsoft.Network/ddosProtectionPlans@2023-09-01' = if (environmentName == 'prod') {
  name: 'ddos-rbc-${environmentName}'
  location: location
  properties: {}
}

// Outputs
output vnetId string = vnet.id
output appServicesSubnetId string = vnet.properties.subnets[0].id
output databaseSubnetId string = vnet.properties.subnets[1].id
output redisSubnetId string = vnet.properties.subnets[2].id
output privateEndpointsSubnetId string = vnet.properties.subnets[3].id
output containerAppsSubnetId string = vnet.properties.subnets[4].id
output privateDnsZoneKeyVaultId string = environmentName == 'prod' ? privateDnsZoneKeyVault.id : ''
output privateDnsZonePostgreSQLId string = environmentName == 'prod' ? privateDnsZonePostgreSQL.id : ''
output privateDnsZoneRedisId string = environmentName == 'prod' ? privateDnsZoneRedis.id : ''
output wafPolicyId string = environmentName == 'prod' ? wafPolicy.id : ''
output ddosProtectionPlanId string = environmentName == 'prod' ? ddosProtectionPlan.id : ''