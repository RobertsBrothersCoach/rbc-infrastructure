// PostgreSQL Connection Pooling Configuration
// Configures PgBouncer for efficient connection management

@description('PostgreSQL server name')
param postgresServerName string

@description('Environment name')
@allowed(['dev', 'qa', 'prod'])
param environmentName string

@description('Location')
param location string = resourceGroup().location

// Connection pool configurations per environment
var poolConfigs = {
  dev: {
    defaultPoolSize: 25
    maxPoolSize: 50
    reservePoolSize: 5
    poolMode: 'transaction'
    maxClientConn: 100
    autoPauseDelay: 60 // minutes
    serverIdleTimeout: 600
    queryWaitTimeout: 120
  }
  qa: {
    defaultPoolSize: 30
    maxPoolSize: 75
    reservePoolSize: 10
    poolMode: 'transaction'
    maxClientConn: 150
    autoPauseDelay: 60 // minutes
    serverIdleTimeout: 600
    queryWaitTimeout: 120
  }
  prod: {
    defaultPoolSize: 50
    maxPoolSize: 100
    reservePoolSize: 20
    poolMode: 'transaction'
    maxClientConn: 500
    autoPauseDelay: 0 // never auto-pause in production
    serverIdleTimeout: 300
    queryWaitTimeout: 60
  }
}

var currentConfig = poolConfigs[environmentName]

// PostgreSQL server reference
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-03-01-preview' existing = {
  name: postgresServerName
}

// Server parameters for connection pooling
resource connectionPoolingParams 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-03-01-preview' = [for config in [
  {
    name: 'max_connections'
    value: string(currentConfig.maxPoolSize + currentConfig.reservePoolSize)
  }
  {
    name: 'shared_preload_libraries'
    value: 'pg_stat_statements,pgaudit'
  }
  {
    name: 'idle_in_transaction_session_timeout'
    value: string(currentConfig.serverIdleTimeout * 1000) // Convert to milliseconds
  }
  {
    name: 'statement_timeout'
    value: string(currentConfig.queryWaitTimeout * 1000) // Convert to milliseconds
  }
]: {
  name: '${postgresServerName}/${config.name}'
  properties: {
    value: config.value
    source: 'user-override'
  }
}]

// PgBouncer configuration as a Container Instance
resource pgBouncer 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: 'pgbouncer-${postgresServerName}'
  location: location
  properties: {
    containers: [
      {
        name: 'pgbouncer'
        properties: {
          image: 'edoburu/pgbouncer:1.22.1'
          resources: {
            requests: {
              cpu: environmentName == 'prod' ? 1 : json('0.5')
              memoryInGB: environmentName == 'prod' ? 2 : 1
            }
          }
          ports: [
            {
              port: 5432
              protocol: 'TCP'
            }
          ]
          environmentVariables: [
            {
              name: 'DATABASES_HOST'
              value: postgresServer.properties.fullyQualifiedDomainName
            }
            {
              name: 'DATABASES_PORT'
              value: '5432'
            }
            {
              name: 'DATABASES_DBNAME'
              value: 'tourbus'
            }
            {
              name: 'POOL_MODE'
              value: currentConfig.poolMode
            }
            {
              name: 'MAX_CLIENT_CONN'
              value: string(currentConfig.maxClientConn)
            }
            {
              name: 'DEFAULT_POOL_SIZE'
              value: string(currentConfig.defaultPoolSize)
            }
            {
              name: 'MAX_DB_CONNECTIONS'
              value: string(currentConfig.maxPoolSize)
            }
            {
              name: 'RESERVE_POOL_SIZE'
              value: string(currentConfig.reservePoolSize)
            }
            {
              name: 'SERVER_IDLE_TIMEOUT'
              value: string(currentConfig.serverIdleTimeout)
            }
            {
              name: 'QUERY_WAIT_TIMEOUT'
              value: string(currentConfig.queryWaitTimeout)
            }
            {
              name: 'AUTH_TYPE'
              value: 'scram-sha-256'
            }
          ]
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'Always'
    ipAddress: {
      type: 'Private'
      ports: [
        {
          port: 5432
          protocol: 'TCP'
        }
      ]
    }
  }
}

// Outputs
output pgBouncerFqdn string = contains(pgBouncer.properties.ipAddress, 'fqdn') ? pgBouncer.properties.ipAddress.fqdn : ''
output pgBouncerIp string = pgBouncer.properties.ipAddress.ip
output connectionPoolingConfig object = {
  environment: environmentName
  defaultPoolSize: currentConfig.defaultPoolSize
  maxPoolSize: currentConfig.maxPoolSize
  maxClientConnections: currentConfig.maxClientConn
  poolMode: currentConfig.poolMode
  autoPauseDelay: currentConfig.autoPauseDelay
}