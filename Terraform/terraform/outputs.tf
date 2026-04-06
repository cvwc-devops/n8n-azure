output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "container_app_name" {
  value = azurerm_container_app.this.name
}

output "container_app_fqdn" {
  value = azurerm_container_app.this.latest_revision_fqdn
}

output "n8n_public_url" {
  value = "https://${var.n8n_host}/"
}

output "generated_ingress_url" {
  value = "https://${azurerm_container_app.this.latest_revision_fqdn}"
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}
