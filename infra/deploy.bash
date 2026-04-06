az deployment group create \
  --resource-group <your-rg> \
  --template-file main.bicep \
  --parameters \
    postgresAdminPassword='<strong-db-password>' \
    n8nBasicAuthUser='admin' \
    n8nBasicAuthPassword='<strong-n8n-password>' \
    n8nHost='n8n.example.com'
