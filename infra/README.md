# n8n Azure Infrastructure

This bundle contains:
- Bicep templates for Azure Container Apps + PostgreSQL Flexible Server
- Key Vault-backed secrets for app runtime configuration
- Private networking for PostgreSQL
- Shared, dev, and prod parameter files
- GitHub Actions workflow for deployment

## Before deploy

1. Replace `REPLACE_WITH_VERSION` in the dev/prod parameter files with the actual Key Vault secret versions.
2. Create GitHub environment secrets for:
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
   - `AZURE_RESOURCE_GROUP`
3. Ensure the service principal has rights to deploy to the target resource group.
4. Ensure the deployment identity can resolve the Key Vault secret used for PostgreSQL server creation.

## Deploy manually

```bash
az deployment group create \
  --resource-group <your-rg> \
  --template-file infra/main.bicep \
  --parameters @infra/main.parameters.json \
  --parameters @infra/parameters/dev.parameters.json
```
