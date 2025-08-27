param environmentName string
param location string
param enableHA bool
param backupRegion string
param keyVaultName string

@secure()
param administratorPassword string

@description('Log Analytics Workspace ID for diagnostic settings')
param logAnalyticsWorkspaceId string = ''

var skuName = environmentName == 'prod' ? 'Standard_D4ds_v4' : 'Standard_B2s'
var storageSizeGB = environmentName == 'prod' ? 256 : 32
var adminUsername = 'rbcadmin'

// Availability zones configuration (only for regions that support zones)
// East US 2 supports zones, West Central US does not
var regionHasZones = contains(['eastus', 'eastus2', 'westus2'], location)
var availabilityZone = (environmentName == 'prod' && regionHasZones) ? '1' : ''

// Reference existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource postgresqlServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: 'psql-rbcleasing-${environmentName}'
  location: location
  sku: {
    name: skuName
    tier: environmentName == 'prod' ? 'GeneralPurpose' : 'Burstable'
  }
  properties: {
    administratorLogin: adminUsername
    administratorLoginPassword: administratorPassword
    version: '15'
    availabilityZone: availabilityZone
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: environmentName == 'prod' ? 35 : 7
      geoRedundantBackup: environmentName == 'prod' ? 'Enabled' : 'Disabled'
    }
    highAvailability: {
      mode: enableHA ? (regionHasZones ? 'ZoneRedundant' : 'SameZone') : 'Disabled'
      standbyAvailabilityZone: (enableHA && regionHasZones) ? '2' : ''
    }
    dataEncryption: {
      type: 'SystemManaged'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Store PostgreSQL admin password in Key Vault
resource postgresAdminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgresql-admin-password'
  properties: {
    value: administratorPassword
  }
}

// Store PostgreSQL connection details in Key Vault
resource postgresConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgresql-connection-string'
  properties: {
    value: 'Server=${postgresqlServer.properties.fullyQualifiedDomainName};Database=tourbus_leasing;User Id=${adminUsername};Password=${administratorPassword};'
  }
}

// Store PostgreSQL server details separately for flexible access
resource postgresServerNameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgresql-server-name'
  properties: {
    value: postgresqlServer.properties.fullyQualifiedDomainName
  }
}

resource postgresUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgresql-username'
  properties: {
    value: adminUsername
  }
}

resource postgresDatabaseSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'postgresql-database'
  properties: {
    value: 'tourbus_leasing'
  }
}

// Database for the application
resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgresqlServer
  name: 'rbc_leasing'
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// Configure audit logging for PII compliance
resource auditLogConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: postgresqlServer
  name: 'log_statement'
  properties: {
    value: environmentName == 'prod' ? 'all' : 'ddl'
    source: 'user-override'
  }
  dependsOn: [
    database  // Ensure database exists first
  ]
}

// Enable query performance insights
resource queryStoreConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: postgresqlServer
  name: 'pg_qs.query_capture_mode'
  properties: {
    value: 'ALL'
    source: 'user-override'
  }
  dependsOn: [
    auditLogConfig  // Run sequentially after audit log config
  ]
}

// Note: auto_pause_delay is not a valid PostgreSQL configuration
// Azure Database for PostgreSQL doesn't support auto-pause like Azure SQL Database
// The autoPause parameter will be ignored for PostgreSQL

// Firewall rules - Allow Azure services only for non-production
resource firewallRuleAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = if (environmentName != 'prod') {
  parent: postgresqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Production uses private endpoints instead of firewall rules
resource firewallRuleProd 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = if (environmentName == 'prod') {
  parent: postgresqlServer
  name: 'DenyPublicAccess'
  properties: {
    startIpAddress: '255.255.255.255'
    endIpAddress: '255.255.255.255' // This effectively blocks all public access
  }
}

// Diagnostic settings for compliance
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  scope: postgresqlServer
  name: 'pii-audit-logs'
  properties: {
    logs: [
      {
        category: 'PostgreSQLLogs'
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

// Output only references to Key Vault secrets, not actual values
output serverName string = postgresqlServer.name
output databaseName string = database.name
output keyVaultSecretUri string = postgresConnectionStringSecret.properties.secretUri
output principalId string = postgresqlServer.identity.principalId