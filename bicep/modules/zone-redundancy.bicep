// Zone Redundancy Configuration Module
// Ensures proper zone redundancy for production deployments in East US 2

@description('Environment name')
param environmentName string

@description('Location for resources')
param location string

// Zone Support Matrix
var zoneSupport = {
  eastus: {
    hasZones: true
    zones: ['1', '2', '3']
    services: {
      postgresql: true
      redis: true
      appService: true
      containerApps: true
      storage: true
      keyvault: false // Key Vault doesn't support zones directly, uses regional redundancy
    }
  }
  eastus2: {
    hasZones: true
    zones: ['1', '2', '3']
    services: {
      postgresql: true
      redis: true
      appService: true
      containerApps: true
      storage: true
      keyvault: false
    }
  }
  westcentralus: {
    hasZones: false
    zones: []
    services: {
      postgresql: false
      redis: false
      appService: false
      containerApps: false
      storage: false
      keyvault: false
    }
  }
  westus2: {
    hasZones: true
    zones: ['1', '2', '3']
    services: {
      postgresql: true
      redis: true
      appService: true
      containerApps: true
      storage: true
      keyvault: false
    }
  }
}

// Get zone configuration for current location
var currentZoneConfig = contains(zoneSupport, location) ? zoneSupport[location] : {
  hasZones: false
  zones: []
  services: {}
}

// Production zone redundancy settings
var isProduction = environmentName == 'prod'
var enableZoneRedundancy = isProduction && currentZoneConfig.hasZones

// PostgreSQL Zone Configuration
output postgresqlZoneConfig object = {
  enableHA: enableZoneRedundancy && currentZoneConfig.services.postgresql
  primaryZone: enableZoneRedundancy ? '1' : ''
  standbyZone: enableZoneRedundancy ? '2' : ''
  backupRedundancy: isProduction ? 'GeoRedundant' : 'LocallyRedundant'
  highAvailability: {
    mode: enableZoneRedundancy ? 'ZoneRedundant' : 'Disabled'
    standbyAvailabilityZone: enableZoneRedundancy ? '2' : ''
  }
}

// Redis Zone Configuration
output redisZoneConfig object = {
  sku: isProduction ? 'Premium' : 'Basic'
  enableZoneRedundancy: enableZoneRedundancy && currentZoneConfig.services.redis
  zones: enableZoneRedundancy ? currentZoneConfig.zones : []
  replicasPerMaster: isProduction ? 2 : 0
  replicasPerPrimary: isProduction ? 2 : 0
  configuration: {
    'maxmemory-policy': 'allkeys-lru'
    'rdb-backup-enabled': isProduction ? 'true' : 'false'
    'rdb-backup-frequency': isProduction ? '60' : ''
    'rdb-backup-max-snapshot-count': isProduction ? '1' : ''
    'aof-backup-enabled': isProduction ? 'true' : 'false'
  }
}

// App Service Zone Configuration  
output appServiceZoneConfig object = {
  sku: isProduction ? 'P1v3' : 'B1'
  capacity: enableZoneRedundancy ? 3 : 1 // Minimum 3 instances for zone redundancy
  zoneRedundant: enableZoneRedundancy && currentZoneConfig.services.appService
  alwaysOn: isProduction
  autoHealEnabled: isProduction
  healthCheckPath: '/health'
  loadBalancing: enableZoneRedundancy ? 'LeastRequests' : 'RoundRobin'
}

// Container Apps Zone Configuration
output containerAppsZoneConfig object = {
  zoneRedundant: enableZoneRedundancy && currentZoneConfig.services.containerApps
  minReplicas: isProduction ? 3 : 0 // Minimum 3 for zone redundancy
  maxReplicas: isProduction ? 30 : 3
  scaleRules: [
    {
      name: 'http-requests'
      http: {
        metadata: {
          concurrentRequests: isProduction ? '100' : '30'
        }
      }
    }
    {
      name: 'cpu-utilization'
      custom: {
        type: 'cpu'
        metadata: {
          type: 'Utilization'
          value: isProduction ? '60' : '70'
        }
      }
    }
    {
      name: 'memory-utilization'
      custom: {
        type: 'memory'
        metadata: {
          type: 'Utilization'
          value: isProduction ? '70' : '80'
        }
      }
    }
  ]
}

// Storage Account Zone Configuration
output storageZoneConfig object = {
  sku: isProduction ? 'Standard_ZRS' : 'Standard_LRS' // ZRS for zone redundancy
  kind: 'StorageV2'
  accessTier: 'Hot'
  supportsHttpsTrafficOnly: true
  minimumTlsVersion: 'TLS1_2'
  allowBlobPublicAccess: false
  networkAcls: {
    defaultAction: isProduction ? 'Deny' : 'Allow'
    bypass: 'AzureServices'
  }
  encryption: {
    services: {
      blob: {
        enabled: true
      }
      file: {
        enabled: true
      }
      table: {
        enabled: true
      }
      queue: {
        enabled: true
      }
    }
    keySource: 'Microsoft.Storage'
  }
}

// Virtual Machine Scale Set Zone Configuration (if needed)
output vmssZoneConfig object = {
  zones: enableZoneRedundancy ? currentZoneConfig.zones : ['1']
  platformFaultDomainCount: enableZoneRedundancy ? 5 : 2
  zoneBalance: enableZoneRedundancy
  overprovision: !isProduction
  upgradePolicy: {
    mode: isProduction ? 'Rolling' : 'Manual'
    rollingUpgradePolicy: isProduction ? {
      maxBatchInstancePercent: 20
      maxUnhealthyInstancePercent: 20
      maxUnhealthyUpgradedInstancePercent: 20
      pauseTimeBetweenBatches: 'PT5S'
    } : null
  }
}

// Load Balancer Zone Configuration
output loadBalancerZoneConfig object = {
  sku: {
    name: isProduction ? 'Standard' : 'Basic'
    tier: 'Regional'
  }
  frontendIPConfigurations: [
    {
      zones: enableZoneRedundancy ? currentZoneConfig.zones : []
      properties: {
        publicIPAddressVersion: 'IPv4'
      }
    }
  ]
}

// Monitoring and Alerting for Zone Health
output zoneHealthMonitoring object = {
  enabled: isProduction
  alerts: [
    {
      name: 'zone-failure-alert'
      description: 'Alert when a zone becomes unhealthy'
      severity: 1
      evaluationFrequency: 'PT1M'
      windowSize: 'PT5M'
    }
    {
      name: 'cross-zone-latency-alert'
      description: 'Alert on high cross-zone latency'
      severity: 2
      evaluationFrequency: 'PT5M'
      windowSize: 'PT15M'
      threshold: 100 // milliseconds
    }
    {
      name: 'zone-imbalance-alert'
      description: 'Alert when traffic is not balanced across zones'
      severity: 3
      evaluationFrequency: 'PT5M'
      windowSize: 'PT15M'
      threshold: 30 // percentage deviation
    }
  ]
  dashboards: [
    {
      name: 'zone-health-dashboard'
      widgets: [
        'Zone Availability Status'
        'Cross-Zone Traffic Distribution'
        'Zone Failover History'
        'Resource Distribution by Zone'
      ]
    }
  ]
}

// Disaster Recovery Configuration
output disasterRecoveryConfig object = {
  enabled: isProduction
  primaryRegion: location
  secondaryRegion: location == 'eastus2' ? 'westcentralus' : 'eastus2'
  rpo: isProduction ? 4 : 24 // Recovery Point Objective in hours
  rto: isProduction ? 1 : 4 // Recovery Time Objective in hours
  backupRetention: isProduction ? 35 : 7 // days
  geoReplication: isProduction
  automaticFailover: isProduction && enableZoneRedundancy
}

// Summary output for validation
output zoneRedundancySummary object = {
  location: location
  environment: environmentName
  hasZoneSupport: currentZoneConfig.hasZones
  availableZones: currentZoneConfig.zones
  zoneRedundancyEnabled: enableZoneRedundancy
  servicesWithZoneRedundancy: enableZoneRedundancy ? [
    currentZoneConfig.services.postgresql ? 'PostgreSQL' : ''
    currentZoneConfig.services.redis ? 'Redis' : ''
    currentZoneConfig.services.appService ? 'App Service' : ''
    currentZoneConfig.services.containerApps ? 'Container Apps' : ''
    currentZoneConfig.services.storage ? 'Storage' : ''
  ] : []
  recommendations: !enableZoneRedundancy && isProduction ? [
    'Consider deploying to a region with availability zone support'
    'Current region ${location} does not support zone redundancy'
    'Recommended regions: eastus, eastus2, westus2'
  ] : []
}