3-file split.

It keeps the same hardened shape as the last version, but separates:

main.bicep for orchestration
network.bicep for VNet, subnets, and private DNS
app.bicep for Log Analytics, Container Apps, PostgreSQL, and Key Vault access
