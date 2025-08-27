@description('Environment name')
param environmentName string

@description('Location for resources')
param location string

@description('Allow list of IP addresses for management access')
param allowedManagementIPs array = []

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
    enableDdosProtection: environmentName == 'prod' ? true : false
    ddosProtectionPlan: environmentName == 'prod' ? {
      id: ddosProtectionPlan.id
    } : null
    subnets: [
      {
        name: 'snet-app-services'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsgAppServices.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.KeyVault'
              locations: [location]
            }
            {
              service: 'Microsoft.Storage'
              locations: [location]
            }
            {
              service: 'Microsoft.Sql'
              locations: [location]
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
          networkSecurityGroup: {
            id: nsgDatabase.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
              locations: [location]
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
          networkSecurityGroup: {
            id: nsgRedis.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: '10.0.4.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-container-apps'
        properties: {
          addressPrefix: '10.0.5.0/24'
          networkSecurityGroup: {
            id: nsgContainerApps.id
          }
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
      {
        name: 'snet-management'
        properties: {
          addressPrefix: '10.0.6.0/24'
          networkSecurityGroup: {
            id: nsgManagement.id
          }
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
        name: 'AllowHTTPSFromInternet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          description: 'Allow HTTPS traffic from Internet'
        }
      }
      {
        name: 'AllowHTTPFromInternet'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: environmentName == 'prod' ? 'Deny' : 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          description: 'Allow HTTP in non-prod, deny in prod'
        }
      }
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          description: 'Allow Azure Load Balancer health probes'
        }
      }
      {
        name: 'AllowVnetCommunication'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          description: 'Allow VNet internal communication'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          description: 'Deny all other inbound traffic'
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
          description: 'Allow PostgreSQL from App Services subnet'
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
          description: 'Allow PostgreSQL from Container Apps subnet'
        }
      }
      {
        name: 'AllowPostgreSQLFromManagement'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: environmentName != 'prod' ? 'Allow' : 'Deny'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5432'
          sourceAddressPrefix: '10.0.6.0/24'
          destinationAddressPrefix: '*'
          description: 'Allow PostgreSQL from Management subnet (non-prod only)'
        }
      }
      {
        name: 'AllowAzureServices'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureCloud'
          destinationAddressPrefix: '*'
          description: 'Allow Azure services'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          description: 'Deny all other inbound traffic'
        }
      }
    ]
  }
}

// Network Security Group for Redis
resource nsgRedis 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-redis-${environmentName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowRedisFromAppServices'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['6379', '6380']
          sourceAddressPrefix: '10.0.1.0/24'
          destinationAddressPrefix: '*'
          description: 'Allow Redis from App Services subnet'
        }
      }
      {
        name: 'AllowRedisFromContainerApps'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['6379', '6380']
          sourceAddressPrefix: '10.0.5.0/24'
          destinationAddressPrefix: '*'
          description: 'Allow Redis from Container Apps subnet'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          description: 'Deny all other inbound traffic'
        }
      }
    ]
  }
}

// Network Security Group for Container Apps
resource nsgContainerApps 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-container-apps-${environmentName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHTTPSFromInternet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          description: 'Allow HTTPS traffic from Internet'
        }
      }
      {
        name: 'AllowHTTPFromInternet'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: environmentName == 'prod' ? 'Deny' : 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          description: 'Allow HTTP in non-prod only'
        }
      }
      {
        name: 'AllowVnetCommunication'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          description: 'Allow VNet internal communication'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          description: 'Deny all other inbound traffic'
        }
      }
    ]
  }
}

// Network Security Group for Management
resource nsgManagement 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-management-${environmentName}'
  location: location
  properties: {
    securityRules: concat([
      {
        name: 'AllowSSHFromAllowedIPs'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: length(allowedManagementIPs) > 0 ? 'Allow' : 'Deny'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefixes: length(allowedManagementIPs) > 0 ? allowedManagementIPs : ['0.0.0.0/32']
          destinationAddressPrefix: '*'
          description: 'Allow SSH from specified IPs only'
        }
      }
      {
        name: 'AllowRDPFromAllowedIPs'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: length(allowedManagementIPs) > 0 ? 'Allow' : 'Deny'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefixes: length(allowedManagementIPs) > 0 ? allowedManagementIPs : ['0.0.0.0/32']
          destinationAddressPrefix: '*'
          description: 'Allow RDP from specified IPs only'
        }
      }
      {
        name: 'AllowBastionCommunication'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRanges: ['8080', '5701']
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          description: 'Allow Bastion communication'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          description: 'Deny all other inbound traffic'
        }
      }
    ])
  }
}

// Private DNS Zones for production
resource privateDnsZoneKeyVault 'Microsoft.Network/privateDnsZones@2020-06-01' = if (environmentName == 'prod') {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  properties: {}
}

resource privateDnsZonePostgreSQL 'Microsoft.Network/privateDnsZones@2020-06-01' = if (environmentName == 'prod') {
  name: 'privatelink.postgres.database.azure.com'
  location: 'global'
  properties: {}
}

resource privateDnsZoneRedis 'Microsoft.Network/privateDnsZones@2020-06-01' = if (environmentName == 'prod') {
  name: 'privatelink.redis.cache.windows.net'
  location: 'global'
  properties: {}
}

resource privateDnsZoneStorage 'Microsoft.Network/privateDnsZones@2020-06-01' = if (environmentName == 'prod') {
  name: 'privatelink.blob.core.windows.net'
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

resource vnetLinkStorage 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (environmentName == 'prod') {
  parent: privateDnsZoneStorage
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
    customRules: [
      {
        name: 'RateLimitRule'
        priority: 1
        ruleType: 'RateLimitRule'
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            operator: 'IPMatch'
            negationConditon: false
            matchValues: [
              '0.0.0.0/0'
            ]
          }
        ]
        action: 'Block'
        rateLimitDuration: 'OneMin'
        rateLimitThreshold: 100
      }
    ]
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 10
      state: 'Enabled'
      mode: 'Prevention'
      requestBodyInspectLimitInKB: 128
      fileUploadEnforcement: true
      requestBodyEnforcement: true
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
          ruleGroupOverrides: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
        }
      ]
      exclusions: []
    }
  }
}

// DDoS Protection Plan for production
resource ddosProtectionPlan 'Microsoft.Network/ddosProtectionPlans@2023-09-01' = if (environmentName == 'prod') {
  name: 'ddos-rbc-${environmentName}'
  location: location
  properties: {}
}

// Network Watcher
resource networkWatcher 'Microsoft.Network/networkWatchers@2023-09-01' = {
  name: 'nw-rbc-${environmentName}'
  location: location
  properties: {}
}

// Flow Logs for NSGs (production only)
resource flowLogsAppServices 'Microsoft.Network/networkWatchers/flowLogs@2023-09-01' = if (environmentName == 'prod') {
  parent: networkWatcher
  name: 'fl-app-services-${environmentName}'
  location: location
  properties: {
    targetResourceId: nsgAppServices.id
    storageId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/RBCLeasingApp-${toUpper(take(environmentName, 1))}${toLower(skip(environmentName, 1))}/providers/Microsoft.Storage/storageAccounts/strbc${environmentName}logs'
    enabled: true
    retentionPolicy: {
      days: 30
      enabled: true
    }
    format: {
      type: 'JSON'
      version: 2
    }
  }
}

// Outputs
output vnetId string = vnet.id
output vnetName string = vnet.name
output appServicesSubnetId string = vnet.properties.subnets[0].id
output databaseSubnetId string = vnet.properties.subnets[1].id
output redisSubnetId string = vnet.properties.subnets[2].id
output privateEndpointsSubnetId string = vnet.properties.subnets[3].id
output containerAppsSubnetId string = vnet.properties.subnets[4].id
output managementSubnetId string = vnet.properties.subnets[5].id
output nsgAppServicesId string = nsgAppServices.id
output nsgDatabaseId string = nsgDatabase.id
output nsgRedisId string = nsgRedis.id
output nsgContainerAppsId string = nsgContainerApps.id
output nsgManagementId string = nsgManagement.id
output privateDnsZoneKeyVaultId string = environmentName == 'prod' ? privateDnsZoneKeyVault.id : ''
output privateDnsZonePostgreSQLId string = environmentName == 'prod' ? privateDnsZonePostgreSQL.id : ''
output privateDnsZoneRedisId string = environmentName == 'prod' ? privateDnsZoneRedis.id : ''
output privateDnsZoneStorageId string = environmentName == 'prod' ? privateDnsZoneStorage.id : ''
output wafPolicyId string = environmentName == 'prod' ? wafPolicy.id : ''
output ddosProtectionPlanId string = environmentName == 'prod' ? ddosProtectionPlan.id : ''