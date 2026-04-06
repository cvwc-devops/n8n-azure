# n8n-azure
n8n azure

### What’s inside:

Azure infra in Bicep for Container Apps, PostgreSQL Flexible Server, and wiring to an existing Key Vault

GitHub Actions deploy pipeline using Azure OIDC login, so you do not need long-lived Azure passwords in GitHub

Key Vault-backed runtime secrets for the Container App, using managed identity and Key Vault secret references, which Azure Container Apps supports
n8n runtime settings for reverse-proxy hosting, including WEBHOOK_URL and N8N_PROXY_HOPS, which n8n recommends for self-hosted deployments behind a proxy
workflow import script that pushes JSON workflows into n8n using an API key; n8n documents API-key auth for the public REST API

One important production note: I set a custom N8N_ENCRYPTION_KEY path through Key Vault because n8n uses that key to encrypt stored credentials, and n8n recommends setting your own stable key for self-hosted deployments.

### Two things to adjust before first run:

Set your real GitHub OIDC app values in repo secrets: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, AZURE_KEYVAULT_NAME. Microsoft and GitHub both document this OIDC pattern.

Seed the Key Vault secrets listed in the README before the pipeline runs.

The sample uses the n8n public API import path in scripts/import-workflows.sh. Since n8n exposes a built-in API playground for self-hosted instances, verify the exact workflow endpoints against your instance version if needed.

