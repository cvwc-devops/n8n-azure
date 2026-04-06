# n8n on Azure with Terraform + GitHub Actions + Key Vault

This repo deploys a basic n8n environment on Azure using:

- Azure Container Apps for n8n
- Azure Database for PostgreSQL Flexible Server
- Azure Key Vault for secrets
- GitHub Actions with Azure OIDC for deployment
- n8n API key for workflow import

## Architecture

- `terraform/` creates:
  - Resource Group
  - Log Analytics Workspace
  - Container Apps Environment
  - PostgreSQL Flexible Server + database
  - Container App for n8n
  - System-assigned managed identity on the Container App
  - RBAC so the Container App can read secrets from Key Vault
- `.github/workflows/deploy.yml`:
  - logs into Azure using OIDC
  - runs Terraform plan/apply
  - discovers the n8n URL
  - imports workflows from `workflows/*.json`

## Prerequisites

1. Azure subscription.
2. Existing Azure Key Vault.
3. GitHub repo.
4. A Microsoft Entra app or user-assigned managed identity configured for GitHub OIDC.

GitHub and Microsoft both recommend OIDC for Azure authentication from Actions instead of storing long-lived Azure secrets. See:
- GitHub OIDC with Azure
- Azure Login with OIDC

## Key Vault secrets to create

Create these secrets in your existing Key Vault before the first deployment:

- `n8n-db-password`
- `n8n-encryption-key`
- `n8n-user-management-jwt-secret`
- `n8n-basic-auth-user`
- `n8n-basic-auth-password`
- `n8n-api-key`

Notes:
- `n8n-encryption-key` must stay stable. n8n uses it to encrypt stored credentials.
- `n8n-api-key` is used by the workflow import job after n8n starts.
- Basic auth is optional but strongly recommended for an internet-facing editor.

Generate strong values, for example:

```bash
openssl rand -hex 32   # encryption key / jwt secret
openssl rand -base64 24
```

## GitHub repository secrets

Add these GitHub Actions secrets:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `TF_STATE_RG`
- `TF_STATE_STORAGE_ACCOUNT`
- `TF_STATE_CONTAINER`
- `TF_VAR_resource_group_name`
- `TF_VAR_location`
- `TF_VAR_name_prefix`
- `TF_VAR_key_vault_name`
- `TF_VAR_n8n_host`

Example:
- `TF_VAR_n8n_host = n8n.example.com`
- `TF_VAR_name_prefix = jackops`

The workflow configures Terraform remote state in Azure Storage using the `TF_STATE_*` secrets.

## DNS and ingress

The Container App is configured for external ingress on port `5678`. Terraform outputs the generated FQDN. Point your DNS name to that endpoint using a CNAME, then front it with your preferred TLS/DNS setup. For production, put n8n behind a stable hostname and set `WEBHOOK_URL` to that public HTTPS URL.

## Deploy

Push to `main` or run the workflow manually.

The workflow will:
1. `terraform init`
2. `terraform apply`
3. query the n8n URL
4. wait for n8n health
5. import any JSON workflow definitions from `workflows/`
6. optionally activate workflows when the JSON includes `active: true`

## Workflow JSON format

Place exported workflow files in `workflows/*.json`.

The import script expects a standard n8n workflow object with at least:
- `name`
- `nodes`
- `connections`

If `active` is set to `true`, the script will call the publish endpoint after create/update.

## Files

- `terraform/main.tf` - main resources
- `terraform/variables.tf` - input variables
- `terraform/outputs.tf` - outputs
- `terraform/versions.tf` - Terraform/provider versions
- `.github/workflows/deploy.yml` - CI/CD pipeline
- `scripts/import-workflows.sh` - imports workflows into n8n
- `workflows/sample-webhook.json` - sample workflow

## Important runtime settings

When n8n is behind a reverse proxy, n8n recommends setting:
- `WEBHOOK_URL`
- `N8N_PROXY_HOPS=1`

This repo sets those values so webhook URLs are generated correctly.

## Hardening ideas

- Put Azure Front Door or Application Gateway in front
- Restrict editor access with IP allow lists or private ingress
- Move to split main/worker/queue mode for scale
- Store Terraform state in a dedicated locked-down subscription
- Enable PostgreSQL high availability and backups based on your RPO/RTO
