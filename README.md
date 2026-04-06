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

These are used only for Azure OIDC login and Key Vault lookup. This avoids storing Azure passwords in GitHub. GitHub recommends OIDC for Azure authentication, and Microsoft documents the same pattern. citeturn605913view3turn605913view2

## Required Key Vault secrets

Create these secrets in your Key Vault before the first deployment:

- `n8n-db-password`
- `n8n-encryption-key`
- `n8n-basic-auth-user`
- `n8n-basic-auth-password`
- `n8n-api-key`
- `n8n-postgres-conn` (optional full connection string if you prefer to use it directly)

n8n recommends setting a custom encryption key instead of letting it generate one locally, because that key is used to encrypt stored credentials. citeturn605913view5

## One-time Azure setup

### 1. Create the resource group

```bash
az group create -n rg-n8n-prod -l westeurope
```

### 2. Create Microsoft Entra app or user-assigned identity for GitHub OIDC

Follow the GitHub + Azure OIDC setup to create a federated credential that trusts your GitHub repo, branch, or environment. OIDC removes the need for long-lived cloud credentials in GitHub Actions. citeturn605913view3turn605913view5

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

The identity used by GitHub Actions needs rights such as **Key Vault Secrets User** on the vault to read secrets during deployment. citeturn605913view2

```bash
az role assignment create \
  --assignee-object-id <github-oidc-principal-object-id> \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope $(az keyvault show -n <your-kv-name> -g rg-n8n-prod --query id -o tsv)
```

## Runtime notes

When n8n is behind a reverse proxy, set `WEBHOOK_URL` explicitly and set `N8N_PROXY_HOPS=1` so webhook URLs are correct. n8n documents both settings for reverse-proxy deployments. citeturn605913view6

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

The GitHub Action retrieves Key Vault secrets with OIDC and masks them before use, matching Microsoft’s documented pattern. citeturn605913view2

## Workflow deployment strategy

This repo uses the **n8n public REST API** with an API key to import workflows from JSON files. n8n documents API-key authentication for the public API. citeturn605913view1turn621265search1

For larger teams using n8n Enterprise, source-control environments are also available natively in n8n. citeturn621265search2turn621265search11

## Files

- `infra/main.bicep` — Azure resources
- `.github/workflows/deploy.yml` — GitHub Actions pipeline
- `scripts/import-workflows.sh` — imports or upserts workflows to n8n
- `workflows/hello-webhook.json` — sample workflow

## Important caveats

- The workflow import script targets the current public API shape exposed by self-hosted n8n. If your instance exposes a different path or schema, adjust the script after checking **Settings -> n8n API** and the built-in API playground. n8n provides a built-in API playground for self-hosted instances. citeturn605913view1
- `latest` is convenient for a starter build, but pinning to a tested n8n tag is safer for production.
