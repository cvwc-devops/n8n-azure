# n8n on Azure - production Terraform starter

This starter deploys a production-leaning n8n environment on Azure with:

- Azure Container Apps in a VNet-integrated environment
- Split n8n roles: `editor`, `webhook`, and `worker`
- PostgreSQL Flexible Server for n8n data
- Azure Cache for Redis for n8n queue mode
- Azure Key Vault for secrets
- User-assigned managed identity for Key Vault secret references
- Azure Front Door Premium in front of the editor and webhook apps
- GitHub Actions using Azure OIDC
- Workflow import to n8n through the public API using an API key

## Architecture

- **editor app**: n8n UI and API, private ingress in Container Apps
- **webhook app**: n8n webhook process, private ingress in Container Apps
- **worker app**: n8n worker process, no public ingress
- **Front Door Premium**: public edge, routes `/webhook/*` to the webhook app and everything else to the editor app
- **Key Vault**: stores DB password, Redis key, n8n encryption key, basic auth, and bootstrap API key

## Assumptions

- You already have a resource group and an existing Key Vault.
- Your Key Vault is reachable by the deployment identity.
- You will seed the required secrets in Key Vault before the first apply.
- You will bring your own DNS and TLS for Front Door custom domains if needed.

## Required Key Vault secrets

Create these secrets in the target vault:

- `n8n-db-password`
- `n8n-encryption-key`
- `n8n-basic-auth-user`
- `n8n-basic-auth-password`
- `n8n-api-key`
- `n8n-redis-key`

> `n8n-redis-key` is created by Terraform only if you choose to read it after Redis deployment and then write it back to Key Vault. For a cleaner split, this starter expects the key in Key Vault already or you can replace Redis auth with access keys fetched at deploy time.

## GitHub repo secrets

Set these GitHub Actions secrets:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `TF_STATE_RG`
- `TF_STATE_STORAGE`
- `TF_STATE_CONTAINER`
- `TF_STATE_KEY`
- `AZURE_RESOURCE_GROUP`
- `AZURE_LOCATION`
- `AZURE_KEYVAULT_NAME`
- `TF_VAR_frontdoor_custom_domain` (optional)

## Bootstrap

```bash
cd terraform
terraform init \
  -backend-config="resource_group_name=$TF_STATE_RG" \
  -backend-config="storage_account_name=$TF_STATE_STORAGE" \
  -backend-config="container_name=$TF_STATE_CONTAINER" \
  -backend-config="key=$TF_STATE_KEY"

terraform apply \
  -var="resource_group_name=<rg>" \
  -var="location=<location>" \
  -var="key_vault_name=<existing-kv>" \
  -var="prefix=<unique-prefix>"
```

After deploy:

1. Read the Front Door endpoint from Terraform output.
2. Update the `webhook_base_url` variable if you want a custom domain.
3. Import workflows with `scripts/import-workflows.sh`.

## Notes

- This starter uses private ingress on Container Apps and Front Door Premium as the internet-facing edge.
- For full lockdown, add private DNS zones, NSGs, UDRs, Defender, backup policies, and secret rotation.
- For real production, put Terraform remote state behind RBAC and private endpoints too.
