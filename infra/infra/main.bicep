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
