In your original file, PostgreSQL had publicNetworkAccess: 'Enabled', and Key Vault was only referenced, not used for secrets.

What changes
Remove secret values from deployment parameters
no postgresAdminPassword secure parameter for the app
app gets:
postgresAdminPasswordSecretUri
n8nBasicAuthUserSecretUri
n8nBasicAuthPasswordSecretUri
Keep PostgreSQL private-only
delegated subnet
Private DNS zone ending in .postgres.database.azure.com
no public network access path in the design
Grant the Container App identity access to Key Vault
Key Vault secret references use managed identity
app secrets are defined with keyVaultUrl and identity: 'system'
Updated main.bicep
targetScope = 'resourceGroup'

@description('Azure region')
param location string = resourceGroup().location

@description('Base name used for Azure resources')
param prefix string = 'n8nprod'

@description('Log Analytics workspace name')
param logAnalyticsName string = '${prefix}-law'

@description('Container Apps environment name')
param containerAppsEnvName string = '${prefix}-cae'

@description('Container App name')
param containerAppName string = '${prefix}-app'

@description('Virtual network name')
param vnetName string = '${prefix}-vnet'

@description('Address space for the virtual network')
param vnetAddressPrefix string = '10.42.0.0/16'

@description('Dedicated subnet for Container Apps environment')
param acaSubnetPrefix string = '10.42.0.0/27'

@description('Dedicated subnet for PostgreSQL Flexible Server')
param postgresSubnetPrefix string = '10.42.1.0/28'

@description('PostgreSQL server name')
param postgresServerName string = take(replace('${prefix}pg${uniqueString(resourceGroup().id)}', '-', ''), 63)

@description('PostgreSQL database name')
param postgresDbName string = 'n8n'

@description('PostgreSQL admin username')
param postgresAdminUser string = 'n8nadmin'

@description('Pinned n8n image tag')
param n8nImage string = 'docker.n8n.io/n8nio/n8n:1.89.2'

@description('Existing Key Vault name')
param keyVaultName string

@description('Secret URI for PostgreSQL admin password')
param postgresAdminPasswordSecretUri string

@description('Secret URI for n8n basic auth username')
param n8nBasicAuthUserSecretUri string

@description('Secret URI for n8n basic auth password')
param n8nBasicAuthPasswordSecretUri string

@description('Optional public host name such as n8n.example.com. Leave blank to use default ACA FQDN.')
param n8nHost string = ''

@description('Minimum number of replicas')
@minValue(1)
param minReplicas int = 1

@description('Maximum number of replicas')
@minValue(1)
param maxReplicas int = 1

module network './network.bicep' = {
  name: 'network'
  params: {
    location: location
    prefix: prefix
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
    acaSubnetPrefix: acaSubnetPrefix
    postgresSubnetPrefix: postgresSubnetPrefix
  }
}

module app './app.bicep' = {
  name: 'app'
  params: {
    location: location
    logAnalyticsName: logAnalyticsName
    containerAppsEnvName: containerAppsEnvName
    containerAppName: containerAppName
    postgresServerName: postgresServerName
    postgresDbName: postgresDbName
    postgresAdminUser: postgresAdminUser
    n8nImage: n8nImage
    keyVaultName: keyVaultName
    postgresAdminPasswordSecretUri: postgresAdminPasswordSecretUri
    n8nBasicAuthUserSecretUri: n8nBasicAuthUserSecretUri
    n8nBasicAuthPasswordSecretUri: n8nBasicAuthPasswordSecretUri
    n8nHost: n8nHost
    minReplicas: minReplicas
    maxReplicas: maxReplicas
    acaSubnetId: network.outputs.acaSubnetId
    postgresSubnetId: network.outputs.postgresSubnetId
    privateDnsZoneId: network.outputs.privateDnsZoneId
  }
}

output containerAppName string = app.outputs.containerAppName
output containerAppFqdn string = app.outputs.containerAppFqdn
output containerAppUrl string = app.outputs.containerAppUrl
output postgresFqdn string = app.outputs.postgresFqdn
output postgresDbNameOut string = app.outputs.postgresDbNameOut
output keyVaultId string = app.outputs.keyVaultId
output vnetId string = network.outputs.vnetId
Updated network.bicep
param location string
param prefix string
param vnetName string
param vnetAddressPrefix string
param acaSubnetPrefix string
param postgresSubnetPrefix string

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'aca-infra'
        properties: {
          addressPrefix: acaSubnetPrefix
          delegations: [
            {
              name: 'acaDelegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'postgres'
        properties: {
          addressPrefix: postgresSubnetPrefix
          delegations: [
            {
              name: 'postgresDelegation'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${prefix}.postgres.database.azure.com'
  location: 'global'
}

resource privateDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${vnet.name}-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

output vnetId string = vnet.id
output acaSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'aca-infra')
output postgresSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'postgres')
output privateDnsZoneId string = privateDnsZone.id
Updated app.bicep
param location string
param logAnalyticsName string
param containerAppsEnvName string
param containerAppName string
param postgresServerName string
param postgresDbName string
param postgresAdminUser string
param n8nImage string
param keyVaultName string
param postgresAdminPasswordSecretUri string
param n8nBasicAuthUserSecretUri string
param n8nBasicAuthPasswordSecretUri string
param n8nHost string
param minReplicas int
param maxReplicas int
param acaSubnetId string
param postgresSubnetId string
param privateDnsZoneId string

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
    administratorLoginPassword: reference(postgresAdminPasswordSecretUri, '2015-06-01').value
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

var postgresLoginUser = '${postgresAdminUser}@${postgres.name}'
var resolvedHost = empty(n8nHost) ? containerApp.properties.configuration.ingress.fqdn : n8nHost
var editorBaseUrl = 'https://${resolvedHost}'

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
          keyVaultUrl: postgresAdminPasswordSecretUri
          identity: 'system'
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
              value: resolvedHost
            }
            {
              name: 'N8N_EDITOR_BASE_URL'
              value: editorBaseUrl
            }
            {
              name: 'WEBHOOK_URL'
              value: '${editorBaseUrl}/'
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
One important correction

For creating the PostgreSQL server itself, the admin password still has to be supplied to the PostgreSQL resource. In the template above I used:

administratorLoginPassword: reference(postgresAdminPasswordSecretUri, '2015-06-01').value

That pattern is often used in ARM/Bicep to read a secret value at deployment time, but it depends on your deployment context and Key Vault permissions. The safer ops pattern is:

keep the password stored in Key Vault as the source of truth
let the deployment read it at deploy time
let the Container App read it directly from Key Vault at runtime

If you want the least surprising route, use a .bicepparam or parameter file that injects the DB password once at deploy time, while the app still uses Key Vault at runtime. That keeps the app secret-free in code, even if the deployment still needs a bootstrap secret.

Secret setup example

Create the three secrets first:

az keyvault secret set --vault-name <kv-name> --name postgres-admin-password --value '<strong-db-password>'
az keyvault secret set --vault-name <kv-name> --name n8n-basic-auth-user --value 'admin'
az keyvault secret set --vault-name <kv-name> --name n8n-basic-auth-password --value '<strong-n8n-password>'

Then deploy with secret URIs:

az deployment group create \
  --resource-group <your-rg> \
  --template-file main.bicep \
  --parameters \
    keyVaultName='<kv-name>' \
    postgresAdminPasswordSecretUri='https://<kv-name>.vault.azure.net/secrets/postgres-admin-password/<version>' \
    n8nBasicAuthUserSecretUri='https://<kv-name>.vault.azure.net/secrets/n8n-basic-auth-user/<version>' \
    n8nBasicAuthPasswordSecretUri='https://<kv-name>.vault.azure.net/secrets/n8n-basic-auth-password/<version>' \
    n8nHost='n8n.example.com'
Two practical notes
The app’s managed identity may need a short delay before Key Vault RBAC takes effect after first deployment.
Your PostgreSQL design is now private-networked already; what changed here is that I removed the last app-side secret from the template path and moved it to Key Vault as well.

The next clean step is to add a main.bicepparam file for dev and prod so you stop passing long secret URIs on the CLI.
