param location string
param prefix string
param logAnalyticsName string
param containerAppsEnvName string
param containerAppName string
param postgresServerName string
param postgresDbName string
param postgresAdminUser string

@secure()
param postgresAdminPassword string

param n8nImage string
param keyVaultName string
param n8nBasicAuthUserSecretUri string
param n8nBasicAuthPasswordSecretUri string
param n8nHost string
param minReplicas int
param maxReplicas int
param acaSubnetId string
param postgresSubnetId string
param privateDnsZoneId string
param privateDnsZoneName string
param vnetId string

var postgresLoginUser = '${postgresAdminUser}@${postgres.name}'
var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4633458b-17de-408a-b874-0445c86b69e6'
)

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

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
    vnetConfiguration: {
      infrastructureSubnetId: acaSubnetId
      internal: false
    }
  }
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-03-01-preview' = {
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
      delegatedSubnetResourceId: postgresSubnetId
      privateDnsZoneArmResourceId: privateDnsZoneId
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
}

resource postgresDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-03-01-preview' = {
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
        allowInsecure: false
      }
      activeRevisionsMode: 'Single'
      secrets: [
        {
          name: 'postgres-password'
          value: postgresAdminPassword
        }
        {
          name: 'n8n-basic-auth-user'
          keyVaultUrl: n8nBasicAuthUserSecretUri
          identity: 'system'
        }
        {
          name: 'n8n-basic-auth-password'
          keyVaultUrl: n8nBasicAuthPasswordSecretUri
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'n8n'
          image: n8nImage
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
              value: postgresLoginUser
            }
            {
              name: 'DB_POSTGRESDB_PASSWORD'
              secretRef: 'postgres-password'
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
              name: 'N8N_HOST'
              value: empty(n8nHost) ? containerApp.properties.configuration.ingress.fqdn : n8nHost
            }
            {
              name: 'N8N_EDITOR_BASE_URL'
              value: empty(n8nHost)
                ? 'https://${containerApp.properties.configuration.ingress.fqdn}'
                : 'https://${n8nHost}'
            }
            {
              name: 'WEBHOOK_URL'
              value: empty(n8nHost)
                ? 'https://${containerApp.properties.configuration.ingress.fqdn}/'
                : 'https://${n8nHost}/'
            }
            {
              name: 'N8N_PROXY_HOPS'
              value: '1'
            }
            {
              name: 'N8N_BASIC_AUTH_ACTIVE'
              value: 'true'
            }
            {
              name: 'N8N_BASIC_AUTH_USER'
              secretRef: 'n8n-basic-auth-user'
            }
            {
              name: 'N8N_BASIC_AUTH_PASSWORD'
              secretRef: 'n8n-basic-auth-password'
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

resource keyVaultSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, containerApp.id, 'kv-secrets-user')
  scope: kv
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output containerAppName string = containerApp.name
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output postgresFqdn string = postgres.properties.fullyQualifiedDomainName
output postgresDbNameOut string = postgresDbName
output keyVaultId string = kv.id
