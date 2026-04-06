az deployment group create \
  --resource-group <your-rg> \
  --template-file main.bicep \
  --parameters \
    keyVaultName='<your-kv-name>' \
    postgresAdminPassword='<strong-db-password>' \
    n8nBasicAuthUserSecretUri='https://<your-kv-name>.vault.azure.net/secrets/n8n-basic-auth-user/<version>' \
    n8nBasicAuthPasswordSecretUri='https://<your-kv-name>.vault.azure.net/secrets/n8n-basic-auth-password/<version>' \
    n8nHost='n8n.example.com'
