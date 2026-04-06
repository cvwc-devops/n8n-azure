@description('Azure region')
param location string = resourceGroup().location

@description('Base name used for Azure resources')
param prefix string = 'n8nprod'

@description('Container App environment name')
param containerAppsEnvName string = '${prefix}-cae'

@description('Container App name')
param containerAppName string = '${prefix}-app'

@description('PostgreSQL server name')
param postgresServerName string = take(replace('${prefix}pg${uniqueString(resourceGroup().id)}','-',''), 63)

@description('PostgreSQL database name')
param postgresDbName string = 'n8n'

@description('PostgreSQL admin username')
param postgresAdminUser string = 'n8nadmin'

@secure()
@description('PostgreSQL admin password')
param postgresAdminPassword string

@description('Log Analytics workspace name')
param logAnalyticsName string = '${prefix}-law'

@description('Key Vault name')
param keyVaultName string

@description('n8n host name such as n8n.example.com. Leave blank to use the default ACA FQDN.')
param n8nHost string = ''

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource managedEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: listKeys(logAnalytics.id, logAnalytics.apiVersion).primarySharedKey
      }
    }
  }
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: postgresServerName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    administratorLogin: postgresAdminUser
    administratorLoginPassword: postgresAdminPassword
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
}

resource postgresDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  parent: postgres
  name: postgresDbName
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: managedEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 5678
        transport: 'auto'
      }
      activeRevisionsMode: 'Single'
      secrets: []
    }
    template: {
      containers: [
        {
          name: 'n8n'
          image: 'docker.n8n.io/n8nio/n8n:latest'
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            {
              name: 'DB_TYPE'
              value: 'postgresdb'
            }
            {
              name: 'DB_POSTGRESDB_HOST'
              value: postgres.properties.fullyQualifiedDomainName
            }
            {
              name: 'DB_POSTGRESDB_PORT'
              value: '5432'
            }
            {
              name: 'DB_POSTGRESDB_DATABASE'
              value: postgresDbName
            }
            {
              name: 'DB_POSTGRESDB_USER'
              value: '${postgresAdminUser}@${postgres.name}'
            }
            {
              name: 'DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED'
              value: 'false'
            }
            {
              name: 'N8N_PORT'
              value: '5678'
            }
            {
              name: 'N8N_PROTOCOL'
              value: 'https'
            }
            {
              name: 'N8N_PROXY_HOPS'
              value: '1'
            }
            {
              name: 'N8N_BASIC_AUTH_ACTIVE'
              value: 'true'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

output containerAppName string = containerApp.name
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppPrincipalId string = containerApp.identity.principalId
output keyVaultId string = kv.id
output postgresFqdn string = postgres.properties.fullyQualifiedDomainName
output postgresAdminUserOut string = '${postgresAdminUser}@${postgres.name}'
output postgresDbNameOut string = postgresDbName
