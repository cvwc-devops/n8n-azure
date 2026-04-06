output "frontdoor_endpoint" {
  value = "https://${azurerm_cdn_frontdoor_endpoint.fd_endpoint.host_name}"
}

output "editor_fqdn" {
  value = azurerm_container_app.editor.latest_revision_fqdn
}

output "webhook_fqdn" {
  value = azurerm_container_app.webhook.latest_revision_fqdn
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.postgres.fqdn
}

output "redis_hostname" {
  value = azurerm_redis_cache.redis.hostname
}
