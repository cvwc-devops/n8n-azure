# n8n on Azure with GitHub Actions and Key Vault

This repo bootstraps a self-hosted n8n environment on Azure and deploys workflows through GitHub Actions.

## Architecture

- **Azure Container Apps** runs the n8n container.
- **Azure Database for PostgreSQL Flexible Server** stores n8n data.
- **Azure Key Vault** stores runtime secrets and deployment secrets.
- **GitHub Actions + OIDC** authenticates to Azure without storing long-lived Azure credentials.
- **Managed Identity** lets the Container App read secrets from Key Vault at runtime.

## What gets deployed

- Resource group scoped Azure resources from `infra/main.bicep`
- Key Vault role assignments for:
  - the GitHub Actions federated identity (to read deployment secrets)
  - the n8n Container App managed identity (to read runtime secrets)
- n8n Container App using the official `docker.n8n.io/n8nio/n8n:latest` image
- Example workflow import from `workflows/*.json`

## Required GitHub repository secrets

Add these in **GitHub -> Settings -> Secrets and variables -> Actions**:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_KEYVAULT_NAME`

These are used only for Azure OIDC login and Key Vault lookup. This avoids storing Azure passwords in GitHub. GitHub recommends OIDC for Azure authentication, and Microsoft documents the same pattern. 

## Required Key Vault secrets

Create these secrets in your Key Vault before the first deployment:

- `n8n-db-password`
- `n8n-encryption-key`
- `n8n-basic-auth-user`
- `n8n-basic-auth-password`
- `n8n-api-key`
- `n8n-postgres-conn` (optional full connection string if you prefer to use it directly)

n8n recommends setting a custom encryption key instead of letting it generate one locally, because that key is used to encrypt stored credentials.

## One-time Azure setup

### 1. Create the resource group

```bash
az group create -n rg-n8n-prod -l westeurope
```

### 2. Create Microsoft Entra app or user-assigned identity for GitHub OIDC

Follow the GitHub + Azure OIDC setup to create a federated credential that trusts your GitHub repo, branch, or environment. OIDC removes the need for long-lived cloud credentials in GitHub Actions. 

Minimal subject example:

```text
repo:<ORG>/<REPO>:ref:refs/heads/main
```

### 3. Create the Key Vault and seed secrets

```bash
az keyvault create -n <your-kv-name> -g rg-n8n-prod -l westeurope --enable-rbac-authorization true

az keyvault secret set --vault-name <your-kv-name> --name n8n-db-password --value '<strong-db-password>'
az keyvault secret set --vault-name <your-kv-name> --name n8n-encryption-key --value '<32+ char stable key>'
az keyvault secret set --vault-name <your-kv-name> --name n8n-basic-auth-user --value 'admin'
az keyvault secret set --vault-name <your-kv-name> --name n8n-basic-auth-password --value '<strong-password>'
az keyvault secret set --vault-name <your-kv-name> --name n8n-api-key --value '<n8n-api-key>'
```

### 4. Grant the GitHub identity access to read Key Vault secrets

The identity used by GitHub Actions needs rights such as **Key Vault Secrets User** on the vault to read secrets during deployment.

```bash
az role assignment create \
  --assignee-object-id <github-oidc-principal-object-id> \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope $(az keyvault show -n <your-kv-name> -g rg-n8n-prod --query id -o tsv)
```

## Runtime notes

When n8n is behind a reverse proxy, set `WEBHOOK_URL` explicitly and set `N8N_PROXY_HOPS=1` so webhook URLs are correct. n8n documents both settings for reverse-proxy deployments. 

## Deployment

Push to `main` or run the workflow manually.

The pipeline does this:

1. Logs into Azure using OIDC.
2. Deploys Azure infrastructure with Bicep.
3. Assigns a managed identity to the Container App.
4. Wires Container App secrets to Key Vault secret references.
5. Restarts the app.
6. Waits for n8n to become reachable.
7. Imports or updates any workflow JSON files in `workflows/` using the n8n API key retrieved from Key Vault.

The GitHub Action retrieves Key Vault secrets with OIDC and masks them before use, matching Microsoft’s documented pattern.

## Workflow deployment strategy

This repo uses the **n8n public REST API** with an API key to import workflows from JSON files. n8n documents API-key authentication for the public API. 

For larger teams using n8n Enterprise, source-control environments are also available natively in n8n. 

## Files

- `infra/main.bicep` — Azure resources
- `.github/workflows/deploy.yml` — GitHub Actions pipeline
- `scripts/import-workflows.sh` — imports or upserts workflows to n8n
- `workflows/hello-webhook.json` — sample workflow

## Important caveats

- The workflow import script targets the current public API shape exposed by self-hosted n8n. If your instance exposes a different path or schema, adjust the script after checking **Settings -> n8n API** and the built-in API playground. n8n provides a built-in API playground for self-hosted instances.
- `latest` is convenient for a starter build, but pinning to a tested n8n tag is safer for production.

## bicep file

Bicep is Microsoft’s language for defining Azure resources in a simpler way than raw ARM JSON. A file named main.bicep commonly acts as the entry point for a deployment.

### What it usually does:

defines Azure resources directly, or
calls other smaller .bicep modules, or
wires parameters, variables, and outputs together

### A typical main.bicep might include:

parameters like location, app name, SKU
resources like storage accounts, VNets, app services
modules like network.bicep, app.bicep, database.bicep
outputs such as resource IDs or endpoints

### Example:

param location string = resourceGroup().location
param storageName string

resource stg 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

output storageId string = stg.id

In practice, main.bicep often means:

top-level deployment file
the one you run with Azure CLI or PowerShell
the file that coordinates the rest of the infrastructure code

### Example deploy command:

az deployment group create \
  --resource-group my-rg \
  --template-file main.bicep

### So, in plain English:
main.bicep is usually the starting file that describes the Azure infrastructure you want to deploy.

### main.bicep file

This main.bicep is an Azure infrastructure template that deploys an n8n setup on Azure Container Apps, plus a PostgreSQL database, Log Analytics workspace, and references an existing Key Vault.

### What it creates:

- a Log Analytics workspace for logs
- an Azure Container Apps managed environment
- a PostgreSQL Flexible Server
- a PostgreSQL database named n8n
- a Container App that runs the n8n Docker image
- a reference to an existing Key Vault by name

### What the parameters mean:

<br><br>location: Azure region<br>
prefix: base naming prefix, default n8nprod<br>
containerAppsEnvName, containerAppName, logAnalyticsName: derived names for resources<br>
postgresServerName: generated PostgreSQL server name<br>
postgresDbName: defaults to n8n<br>
postgresAdminUser: defaults to n8nadmin<br>
postgresAdminPassword: secure parameter, must be supplied<br>
keyVaultName: required existing Key Vault name<br>
n8nHost: optional hostname, but it is not actually used anywhere else in this file<br>

### How the app is configured:

<br><br>The Container App runs docker.n8n.io/n8nio/n8n:latest<br>
It exposes port 5678<br>
It uses PostgreSQL as the backend database<br>
It enables basic auth<br>
It forces HTTPS-related settings like N8N_PROTOCOL=https<br>
It is fixed at 1 replica minimum and 1 replica maximum<br>

### A few important things I notice:

<br><br>Database password is not wired into the container app. The app sets host, port, DB name, and DB user, but I do not see DB_POSTGRESDB_PASSWORD in the container environment variables. As written, n8n likely will not be able to connect to PostgreSQL successfully.<br>
Key Vault is only referenced, not used. The template outputs the Key Vault ID, but it does not store secrets there or pull secrets from it.<br>
n8nHost is unused. It is declared as a parameter, but nothing in the deployment applies it to ingress, custom domains, or env vars.<br>
PostgreSQL public network access is enabled. That is simpler to get running, but less locked down.
It uses n8n:latest, which is convenient but less predictable for production because upgrades can change behavior unexpectedly.

### Outputs you get after deployment:

- container app name
- container app FQDN
- container app managed identity principal ID
- Key Vault ID
- PostgreSQL FQDN
- PostgreSQL login username
- database name

In plain English: this file is trying to stand up a basic production-style n8n environment on Azure, but it looks incomplete because the app is missing the PostgreSQL password configuration.
<br><br>
The biggest fix is usually to add a secret and reference it from the container app, for example by adding a container app secret and then setting DB_POSTGRESDB_PASSWORD from that secret.


