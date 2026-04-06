# n8n on Azure with GitHub Actions

This is an opinionated production-ready starter for:

- hosting **n8n** on **Azure Container Apps**
- storing state in **Azure Database for PostgreSQL Flexible Server**
- deploying from **GitHub Actions** using **Azure OIDC**
- promoting workflow JSON files from Git to n8n after app deploy

It is designed to be simple first, then scalable.

---

## Architecture

- **Azure Container Apps**: runs the n8n container
- **Azure Container Apps Environment**: shared hosting environment
- **Azure Container Registry**: stores the n8n image
- **Azure Database for PostgreSQL Flexible Server**: n8n database
- **Log Analytics**: container logs and diagnostics
- **GitHub Actions**: CI/CD using Azure federated identity (OIDC)

For first deployment, run **single-instance main mode**. For higher throughput, extend this to **queue mode** with Redis and worker apps.

---

## Repo layout

```text
.
├── .github/
│   └── workflows/
│       ├── deploy-infra.yml
│       └── deploy-n8n.yml
├── infra/
│   ├── main.bicep
│   ├── main.parameters.json
│   └── modules/
│       ├── acr.bicep
│       ├── log-analytics.bicep
│       ├── postgres.bicep
│       ├── containerapp-env.bicep
│       └── n8n-app.bicep
├── scripts/
│   ├── deploy-workflows.sh
│   └── wait-for-n8n.sh
├── workflows/
│   └── hello-world.json
├── Dockerfile
├── .dockerignore
└── README.md
```

---

## 1) Dockerfile

```dockerfile
FROM docker.n8n.io/n8nio/n8n:stable

USER root
RUN apk add --no-cache bash curl jq
USER node
```

---

## 2) .dockerignore

```gitignore
.git
.github
node_modules
.env
*.log
```

---

## 3) Bicep: infra/main.bicep

```bicep
targetScope = 'resourceGroup'

@description('Azure region')
param location string = resourceGroup().location

@description('Base name used for resources')
param prefix string

@description('Container app name')
param containerAppName string = '${prefix}-n8n'

@description('Container Apps environment name')
param containerEnvName string = '${prefix}-aca-env'

@description('ACR name - must be globally unique and 5-50 alphanumeric')
param acrName string

@description('Log Analytics workspace name')
param logAnalyticsName string = '${prefix}-logs'

@description('PostgreSQL server name - must be globally unique')
param postgresServerName string

@description('PostgreSQL database name')
param postgresDbName string = 'n8n'

@description('PostgreSQL admin username')
param postgresAdminUser string

@secure()
@description('PostgreSQL admin password')
param postgresAdminPassword string

@secure()
@description('n8n encryption key')
param n8nEncryptionKey string

@description('Public n8n URL, for example https://n8n.example.com')
param n8nPublicUrl string

@description('n8n container image tag')
param imageTag string = 'stable'

var dbHost = '${postgresServerName}.postgres.database.azure.com'
var dbUser = '${postgresAdminUser}'

module logs './modules/log-analytics.bicep' = {
  name: 'logs'
  params: {
    name: logAnalyticsName
    location: location
  }
}

module acr './modules/acr.bicep' = {
  name: 'acr'
  params: {
    name: acrName
    location: location
  }
}

module env './modules/containerapp-env.bicep' = {
  name: 'aca-env'
  params: {
    name: containerEnvName
    location: location
    logAnalyticsCustomerId: logs.outputs.customerId
    logAnalyticsSharedKey: logs.outputs.sharedKey
  }
}

module postgres './modules/postgres.bicep' = {
  name: 'postgres'
  params: {
    name: postgresServerName
    location: location
    adminUser: postgresAdminUser
    adminPassword: postgresAdminPassword
    databaseName: postgresDbName
  }
}

module app './modules/n8n-app.bicep' = {
  name: 'n8n-app'
  params: {
    name: containerAppName
    location: location
    managedEnvironmentId: env.outputs.id
    acrLoginServer: acr.outputs.loginServer
    imageName: 'n8n'
    imageTag: imageTag
    n8nEncryptionKey: n8nEncryptionKey
    n8nPublicUrl: n8nPublicUrl
    dbHost: dbHost
    dbPort: '5432'
    dbName: postgresDbName
    dbUser: dbUser
    dbPassword: postgresAdminPassword
  }
}

output acrLoginServer string = acr.outputs.loginServer
output containerAppFqdn string = app.outputs.fqdn
output containerAppName string = app.outputs.name
output postgresHost string = dbHost
output postgresDb string = postgresDbName
```

---

## 4) Bicep: infra/modules/log-analytics.bicep

```bicep
param name string
param location string

resource workspace 'Microsoft.OperationalInsights/workspaces@2026-06-01' = {
  name: name
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

output customerId string = workspace.properties.customerId
output sharedKey string = listKeys(workspace.id, '2026-06-01').primarySharedKey
```

---

## 5) Bicep: infra/modules/acr.bicep

```bicep
param name string
param location string

resource acr 'Microsoft.ContainerRegistry/registries@2026-06-01' = {
  name: name
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

output loginServer string = acr.properties.loginServer
output id string = acr.id
```

---

## 6) Bicep: infra/modules/containerapp-env.bicep

```bicep
param name string
param location string
param logAnalyticsCustomerId string
@secure()
param logAnalyticsSharedKey string

resource env 'Microsoft.App/managedEnvironments@2026-06-01' = {
  name: name
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
  }
}

output id string = env.id
```

---

## 7) Bicep: infra/modules/postgres.bicep

```bicep
param name string
param location string
param adminUser string
@secure()
param adminPassword string
param databaseName string

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2026-06-01' = {
  name: name
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: adminUser
    administratorLoginPassword: adminPassword
    version: '16'
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

resource db 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2026-06-01' = {
  parent: server
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}
```

---

## 8) Bicep: infra/modules/n8n-app.bicep

```bicep
param name string
param location string
param managedEnvironmentId string
param acrLoginServer string
param imageName string
param imageTag string
@secure()
param n8nEncryptionKey string
param n8nPublicUrl string
param dbHost string
param dbPort string
param dbName string
param dbUser string
@secure()
param dbPassword string

var noProtoUrl = replace(replace(n8nPublicUrl, 'https://', ''), 'http://', '')
var hostOnly = contains(noProtoUrl, '/') ? split(noProtoUrl, '/')[0] : noProtoUrl

resource app 'Microsoft.App/containerApps@2026-06-01' = {
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: managedEnvironmentId
    configuration: {
      ingress: {
        external: true
        targetPort: 5678
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: acrLoginServer
          identity: 'system'
        }
      ]
      secrets: [
        {
          name: 'db-password'
          value: dbPassword
        }
        {
          name: 'n8n-encryption-key'
          value: n8nEncryptionKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'n8n'
          image: '${acrLoginServer}/${imageName}:${imageTag}'
          env: [
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
              value: hostOnly
            }
            {
              name: 'WEBHOOK_URL'
              value: '${n8nPublicUrl}/'
            }
            {
              name: 'N8N_PROXY_HOPS'
              value: '1'
            }
            {
              name: 'N8N_EDITOR_BASE_URL'
              value: '${n8nPublicUrl}/'
            }
            {
              name: 'GENERIC_TIMEZONE'
              value: 'Europe/Dublin'
            }
            {
              name: 'DB_TYPE'
              value: 'postgresdb'
            }
            {
              name: 'DB_POSTGRESDB_HOST'
              value: dbHost
            }
            {
              name: 'DB_POSTGRESDB_PORT'
              value: dbPort
            }
            {
              name: 'DB_POSTGRESDB_DATABASE'
              value: dbName
            }
            {
              name: 'DB_POSTGRESDB_USER'
              value: dbUser
            }
            {
              name: 'DB_POSTGRESDB_PASSWORD'
              secretRef: 'db-password'
            }
            {
              name: 'N8N_ENCRYPTION_KEY'
              secretRef: 'n8n-encryption-key'
            }
            {
              name: 'N8N_DIAGNOSTICS_ENABLED'
              value: 'false'
            }
            {
              name: 'N8N_PERSONALIZATION_ENABLED'
              value: 'false'
            }
          ]
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
output name string = app.name
output principalId string = app.identity.principalId
```

---

## 9) Parameters: infra/main.parameters.json

Replace the placeholders.

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "prefix": { "value": "jack-prod" },
    "acrName": { "value": "jackprodn8nacr01" },
    "postgresServerName": { "value": "jack-prodn8n-pg-01" },
    "postgresAdminUser": { "value": "n8nadmin" },
    "postgresAdminPassword": { "value": "REPLACE_ME" },
    "n8nEncryptionKey": { "value": "REPLACE_WITH_LONG_RANDOM_SECRET" },
    "n8nPublicUrl": { "value": "https://n8n.example.com" }
  }
}
```

---

## 10) GitHub Actions: deploy infrastructure

`.github/workflows/deploy-infra.yml`

```yaml
name: deploy-infra

on:
  workflow_dispatch:
  push:
    branches: [main]
    paths:
      - 'infra/**'
      - '.github/workflows/deploy-infra.yml'

permissions:
  id-token: write
  contents: read

env:
  RESOURCE_GROUP: rg-jack-n8n-prod
  LOCATION: westeurope

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Azure login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Ensure resource group exists
        run: |
          az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION"

      - name: Deploy Bicep
        run: |
          az deployment group create \
            --resource-group "$RESOURCE_GROUP" \
            --template-file infra/main.bicep \
            --parameters @infra/main.parameters.json \
            --parameters postgresAdminPassword='${{ secrets.POSTGRES_ADMIN_PASSWORD }}' \
            --parameters n8nEncryptionKey='${{ secrets.N8N_ENCRYPTION_KEY }}' \
            --parameters n8nPublicUrl='${{ secrets.N8N_PUBLIC_URL }}'
```

---

## 11) GitHub Actions: build image, deploy app, then push workflows

`.github/workflows/deploy-n8n.yml`

```yaml
name: deploy-n8n

on:
  workflow_dispatch:
  push:
    branches: [main]
    paths:
      - 'Dockerfile'
      - 'scripts/**'
      - 'workflows/**'
      - '.github/workflows/deploy-n8n.yml'

permissions:
  id-token: write
  contents: read

env:
  RESOURCE_GROUP: rg-jack-n8n-prod
  CONTAINER_APP_NAME: jack-prod-n8n
  ACR_NAME: jackprodn8nacr01
  IMAGE_NAME: n8n

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Azure login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: ACR login
        run: az acr login --name "$ACR_NAME"

      - name: Build and push image
        run: |
          ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)
          docker build -t "$ACR_LOGIN_SERVER/$IMAGE_NAME:${GITHUB_SHA}" .
          docker push "$ACR_LOGIN_SERVER/$IMAGE_NAME:${GITHUB_SHA}"
          echo "ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER" >> $GITHUB_ENV

      - name: Update container app image
        run: |
          az containerapp update \
            --name "$CONTAINER_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --image "$ACR_LOGIN_SERVER/$IMAGE_NAME:${GITHUB_SHA}"

      - name: Wait for n8n
        env:
          N8N_BASE_URL: ${{ secrets.N8N_PUBLIC_URL }}
        run: bash scripts/wait-for-n8n.sh

      - name: Deploy workflows to n8n
        env:
          N8N_BASE_URL: ${{ secrets.N8N_PUBLIC_URL }}
          N8N_API_KEY: ${{ secrets.N8N_API_KEY }}
        run: bash scripts/deploy-workflows.sh
```

---

## 12) Script: wait for service

`scripts/wait-for-n8n.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${N8N_BASE_URL:?N8N_BASE_URL is required}"

for i in $(seq 1 60); do
  code=$(curl -k -s -o /dev/null -w "%{http_code}" "$N8N_BASE_URL/healthz" || true)
  if [ "$code" = "200" ] || [ "$code" = "204" ]; then
    echo "n8n is ready"
    exit 0
  fi

  code_root=$(curl -k -s -o /dev/null -w "%{http_code}" "$N8N_BASE_URL" || true)
  if [ "$code_root" = "200" ] || [ "$code_root" = "302" ]; then
    echo "n8n is responding"
    exit 0
  fi

  echo "waiting for n8n... attempt $i"
  sleep 10
done

echo "n8n did not become ready in time"
exit 1
```

---

## 13) Script: workflow deployment

This script treats files in `workflows/*.json` as the source of truth.

Convention:
- each workflow JSON file must include a unique `name`
- if a workflow with that name exists, update it
- otherwise create it

`scripts/deploy-workflows.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

: "${N8N_BASE_URL:?N8N_BASE_URL is required}"
: "${N8N_API_KEY:?N8N_API_KEY is required}"

API_BASE="${N8N_BASE_URL%/}/api/v1"
AUTH_HEADER="X-N8N-API-KEY: ${N8N_API_KEY}"

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required binary: $1"
    exit 1
  }
}

require_bin curl
require_bin jq

fetch_existing_workflow_id() {
  local wf_name="$1"
  curl -fsS \
    -H "$AUTH_HEADER" \
    -H 'accept: application/json' \
    "$API_BASE/workflows?limit=250" \
  | jq -r --arg NAME "$wf_name" '
      if type == "object" and .data then .data
      else .
      end
      | map(select(.name == $NAME))
      | first
      | .id // empty
    '
}

normalize_payload() {
  local file="$1"
  jq '{
      name,
      nodes,
      connections,
      settings: (.settings // {}),
      staticData: (.staticData // null),
      pinData: (.pinData // {}),
      meta: (.meta // null),
      active: (.active // false),
      tags: (.tags // [])
    }' "$file"
}

create_workflow() {
  local file="$1"
  local payload="$2"
  echo "creating workflow from $file"

  curl -fsS -X POST \
    -H "$AUTH_HEADER" \
    -H 'accept: application/json' \
    -H 'content-type: application/json' \
    "$API_BASE/workflows" \
    --data "$payload" >/dev/null
}

update_workflow() {
  local workflow_id="$1"
  local file="$2"
  local payload="$3"
  echo "updating workflow $workflow_id from $file"

  curl -fsS -X PATCH \
    -H "$AUTH_HEADER" \
    -H 'accept: application/json' \
    -H 'content-type: application/json' \
    "$API_BASE/workflows/$workflow_id" \
    --data "$payload" >/dev/null
}

for file in workflows/*.json; do
  name=$(jq -r '.name' "$file")

  if [ -z "$name" ] || [ "$name" = "null" ]; then
    echo "skipping $file: missing workflow name"
    continue
  fi

  payload=$(normalize_payload "$file")
  existing_id=$(fetch_existing_workflow_id "$name")

  if [ -n "$existing_id" ]; then
    update_workflow "$existing_id" "$file" "$payload"
  else
    create_workflow "$file" "$payload"
  fi
done

echo "workflow deployment complete"
```

---

## 14) Example workflow

`workflows/hello-world.json`

```json
{
  "name": "hello-world-webhook",
  "nodes": [
    {
      "parameters": {
        "httpMethod": "GET",
        "path": "hello-world",
        "responseMode": "responseNode"
      },
      "id": "Webhook_1",
      "name": "Webhook",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 2,
      "position": [260, 300],
      "webhookId": "hello-world-webhook"
    },
    {
      "parameters": {
        "respondWith": "json",
        "responseBody": "={\"ok\":true,\"message\":\"hello from azure n8n\"}",
        "options": {}
      },
      "id": "Respond_1",
      "name": "Respond to Webhook",
      "type": "n8n-nodes-base.respondToWebhook",
      "typeVersion": 1,
      "position": [520, 300]
    }
  ],
  "connections": {
    "Webhook": {
      "main": [
        [
          {
            "node": "Respond to Webhook",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  },
  "settings": {},
  "active": false,
  "versionId": "d1de3f2d-b2fd-4d74-a9b7-helloexample"
}
```

---

## 15) Required GitHub secrets

Set these in your repository:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `POSTGRES_ADMIN_PASSWORD`
- `N8N_ENCRYPTION_KEY`
- `N8N_PUBLIC_URL`
- `N8N_API_KEY`

---

## 16) Azure OIDC setup

Create an Azure app registration or user-assigned identity for GitHub Actions and add a federated credential for your repo and branch.

Typical subject:

```text
repo:<org-or-user>/<repo>:ref:refs/heads/main
```

Grant it at least:

- `Contributor` on the resource group
- `AcrPush` on the ACR

---

## 17) First-run steps

1. Push the repo.
2. Configure GitHub OIDC and repository secrets.
3. Run `deploy-infra`.
4. Run `deploy-n8n`.
5. Open your n8n URL and complete first-time owner setup.
6. In n8n, create an API key in **Settings -> n8n API**.
7. Save that key to GitHub as `N8N_API_KEY`.
8. Re-run `deploy-n8n` to promote workflows.

---

## 18) What to improve next

### Add a custom domain and certificate
Use Azure Container Apps custom domain support or front the app with Azure Front Door / Application Gateway.

### Lock down PostgreSQL networking
Move PostgreSQL behind private access instead of public access.

### Add queue mode for scale
Use:
- Azure Cache for Redis
- one **editor/webhook** Container App
- one or more **worker** Container Apps
- `EXECUTIONS_MODE=queue`
- queue-mode Redis environment variables

### Manage credentials safely
Do not store exported credentials in Git. Store secrets in Azure Key Vault and create credentials inside n8n, or use enterprise features if you have them.

---

## 19) Why this design

- It avoids long-lived Azure secrets by using **GitHub OIDC**.
- It uses **PostgreSQL**, which n8n supports for self-hosted production.
- It keeps workflow JSON in Git and promotes them through CI/CD.
- It starts simple enough to get running quickly, but leaves a clean path to queue mode later.

---

## 20) Notes that matter

- n8n uses `WEBHOOK_URL` and proxy settings when it sits behind a reverse proxy.
- Keep `N8N_ENCRYPTION_KEY` stable across redeployments or credentials break.
- The workflow deployment script assumes the public API can list, create, and update workflows with an API key.
- If your n8n edition or policy blocks API-based workflow promotion, switch the promotion step to a CLI-based import job against the running container.

---

## README quickstart

```md
# n8n on Azure

## Deploy infra
Run GitHub Actions workflow: `deploy-infra`

## Deploy app and workflows
Run GitHub Actions workflow: `deploy-n8n`

## Test
After importing the sample workflow, call:

GET https://<your-domain>/webhook/hello-world
```
