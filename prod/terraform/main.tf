locals {
  name = var.prefix
  kv_rg = coalesce(var.key_vault_resource_group_name, var.resource_group_name)
}

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

data "azurerm_key_vault" "kv" {
  name                = var.key_vault_name
  resource_group_name = local.kv_rg
}

data "azurerm_key_vault_secret" "db_password" {
  name         = "n8n-db-password"
  key_vault_id = data.azurerm_key_vault.kv.id
}

data "azurerm_key_vault_secret" "encryption_key" {
  name         = "n8n-encryption-key"
  key_vault_id = data.azurerm_key_vault.kv.id
}

data "azurerm_key_vault_secret" "basic_auth_user" {
  name         = "n8n-basic-auth-user"
  key_vault_id = data.azurerm_key_vault.kv.id
}

data "azurerm_key_vault_secret" "basic_auth_password" {
  name         = "n8n-basic-auth-password"
  key_vault_id = data.azurerm_key_vault.kv.id
}

data "azurerm_key_vault_secret" "api_key" {
  name         = "n8n-api-key"
  key_vault_id = data.azurerm_key_vault.kv.id
}

data "azurerm_key_vault_secret" "redis_key" {
  name         = "n8n-redis-key"
  key_vault_id = data.azurerm_key_vault.kv.id
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${local.name}-vnet"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.40.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "aca_infra" {
  name                 = "aca-infra"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.container_app_env_cidr]
  delegation {
    name = "aca-delegation"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.infra_subnet_cidr]
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "${local.name}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "uami" {
  name                = "${local.name}-uami"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = data.azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.uami.principal_id
}

resource "azurerm_container_app_environment" "env" {
  name                       = "${local.name}-cae"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  infrastructure_subnet_id   = azurerm_subnet.aca_infra.id
  internal_load_balancer_enabled = true
  tags                       = var.tags
}

resource "random_string" "postgres_suffix" {
  length  = 6
  lower   = true
  upper   = false
  special = false
}

resource "azurerm_postgresql_flexible_server" "postgres" {
  name                   = "${local.name}-pg-${random_string.postgres_suffix.result}"
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = "16"
  delegated_subnet_id    = null
  administrator_login    = var.postgres_admin_username
  administrator_password = data.azurerm_key_vault_secret.db_password.value
  zone                   = "1"
  storage_mb             = var.postgres_storage_mb
  sku_name               = var.postgres_sku_name
  public_network_access_enabled = true
  tags                   = var.tags
}

resource "azurerm_postgresql_flexible_server_database" "n8n" {
  name      = "n8n"
  server_id = azurerm_postgresql_flexible_server.postgres.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_redis_cache" "redis" {
  name                = "${local.name}-redis"
  location            = var.location
  resource_group_name = var.resource_group_name
  capacity            = var.redis_capacity
  family              = var.redis_family
  sku_name            = var.redis_sku_name
  enable_non_ssl_port = false
  minimum_tls_version = "1.2"
  redis_configuration {}
  tags                = var.tags
}

locals {
  public_host     = var.frontdoor_custom_domain != "" ? var.frontdoor_custom_domain : azurerm_cdn_frontdoor_endpoint.fd_endpoint.host_name
  webhook_base    = var.webhook_base_url != "" ? var.webhook_base_url : "https://${local.public_host}"
  base_env = [
    { name = "DB_TYPE", value = "postgresdb" },
    { name = "DB_POSTGRESDB_HOST", value = azurerm_postgresql_flexible_server.postgres.fqdn },
    { name = "DB_POSTGRESDB_PORT", value = "5432" },
    { name = "DB_POSTGRESDB_DATABASE", value = azurerm_postgresql_flexible_server_database.n8n.name },
    { name = "DB_POSTGRESDB_USER", value = "${var.postgres_admin_username}" },
    { name = "N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS", value = "true" },
    { name = "N8N_HOST", value = local.public_host },
    { name = "N8N_PROTOCOL", value = "https" },
    { name = "N8N_PORT", value = "5678" },
    { name = "N8N_EDITOR_BASE_URL", value = "https://${local.public_host}" },
    { name = "WEBHOOK_URL", value = local.webhook_base },
    { name = "N8N_PROXY_HOPS", value = "1" },
    { name = "N8N_SECURE_COOKIE", value = "true" },
    { name = "N8N_BASIC_AUTH_ACTIVE", value = "true" },
    { name = "QUEUE_BULL_REDIS_HOST", value = azurerm_redis_cache.redis.hostname },
    { name = "QUEUE_BULL_REDIS_PORT", value = "6380" },
    { name = "QUEUE_BULL_REDIS_TLS", value = "true" },
    { name = "EXECUTIONS_MODE", value = "queue" },
    { name = "N8N_RUNNERS_ENABLED", value = "true" }
  ]
}

resource "azurerm_container_app" "editor" {
  name                         = "${local.name}-editor"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.uami.id]
  }

  secret {
    name                = "db-password"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.db_password.versionless_id
  }
  secret {
    name                = "encryption-key"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.encryption_key.versionless_id
  }
  secret {
    name                = "basic-auth-user"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.basic_auth_user.versionless_id
  }
  secret {
    name                = "basic-auth-password"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.basic_auth_password.versionless_id
  }
  secret {
    name                = "api-key"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.api_key.versionless_id
  }
  secret {
    name                = "redis-key"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.redis_key.versionless_id
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = false
    target_port                = 5678
    transport                  = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.editor_min_replicas
    max_replicas = var.editor_max_replicas
    container {
      name   = "editor"
      image  = var.n8n_image
      cpu    = 1
      memory = "2Gi"
      args   = ["start"]
      dynamic "env" {
        for_each = local.base_env
        content {
          name  = env.value.name
          value = env.value.value
        }
      }
      env { name = "DB_POSTGRESDB_PASSWORD" secret_name = "db-password" }
      env { name = "N8N_ENCRYPTION_KEY" secret_name = "encryption-key" }
      env { name = "N8N_BASIC_AUTH_USER" secret_name = "basic-auth-user" }
      env { name = "N8N_BASIC_AUTH_PASSWORD" secret_name = "basic-auth-password" }
      env { name = "N8N_PUBLIC_API_KEY" secret_name = "api-key" }
      env { name = "QUEUE_BULL_REDIS_PASSWORD" secret_name = "redis-key" }
    }
  }
}

resource "azurerm_container_app" "webhook" {
  name                         = "${local.name}-webhook"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.uami.id]
  }

  secret {
    name                = "db-password"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.db_password.versionless_id
  }
  secret {
    name                = "encryption-key"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.encryption_key.versionless_id
  }
  secret {
    name                = "basic-auth-user"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.basic_auth_user.versionless_id
  }
  secret {
    name                = "basic-auth-password"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.basic_auth_password.versionless_id
  }
  secret {
    name                = "redis-key"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.redis_key.versionless_id
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = false
    target_port                = 5678
    transport                  = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.webhook_min_replicas
    max_replicas = var.webhook_max_replicas
    http_scale_rule {
      name                = "http-scale"
      concurrent_requests = 50
    }
    container {
      name   = "webhook"
      image  = var.n8n_image
      cpu    = 1
      memory = "2Gi"
      args   = ["webhook"]
      dynamic "env" {
        for_each = local.base_env
        content {
          name  = env.value.name
          value = env.value.value
        }
      }
      env { name = "DB_POSTGRESDB_PASSWORD" secret_name = "db-password" }
      env { name = "N8N_ENCRYPTION_KEY" secret_name = "encryption-key" }
      env { name = "N8N_BASIC_AUTH_USER" secret_name = "basic-auth-user" }
      env { name = "N8N_BASIC_AUTH_PASSWORD" secret_name = "basic-auth-password" }
      env { name = "QUEUE_BULL_REDIS_PASSWORD" secret_name = "redis-key" }
    }
  }
}

resource "azurerm_container_app" "worker" {
  name                         = "${local.name}-worker"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.uami.id]
  }

  secret {
    name                = "db-password"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.db_password.versionless_id
  }
  secret {
    name                = "encryption-key"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.encryption_key.versionless_id
  }
  secret {
    name                = "redis-key"
    identity            = azurerm_user_assigned_identity.uami.id
    key_vault_secret_id = data.azurerm_key_vault_secret.redis_key.versionless_id
  }

  template {
    min_replicas = var.worker_min_replicas
    max_replicas = var.worker_max_replicas
    container {
      name   = "worker"
      image  = var.n8n_image
      cpu    = 1
      memory = "2Gi"
      args   = ["worker", "--concurrency=${var.worker_concurrency}"]
      dynamic "env" {
        for_each = local.base_env
        content {
          name  = env.value.name
          value = env.value.value
        }
      }
      env { name = "DB_POSTGRESDB_PASSWORD" secret_name = "db-password" }
      env { name = "N8N_ENCRYPTION_KEY" secret_name = "encryption-key" }
      env { name = "QUEUE_BULL_REDIS_PASSWORD" secret_name = "redis-key" }
    }
  }
}

resource "azurerm_cdn_frontdoor_profile" "fd" {
  name                = "${local.name}-fd"
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "fd_endpoint" {
  name                     = replace("${local.name}-fd-endpoint", "_", "-")
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.fd.id
  enabled                  = true
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "editor" {
  name                     = "editor-og"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.fd.id
  session_affinity_enabled = false
  load_balancing { sample_size = 4 successful_samples_required = 3 }
  health_probe { interval_in_seconds = 120 path = "/healthz" protocol = "Https" request_type = "GET" }
}

resource "azurerm_cdn_frontdoor_origin_group" "webhook" {
  name                     = "webhook-og"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.fd.id
  session_affinity_enabled = false
  load_balancing { sample_size = 4 successful_samples_required = 3 }
  health_probe { interval_in_seconds = 120 path = "/healthz" protocol = "Https" request_type = "GET" }
}

resource "azurerm_cdn_frontdoor_origin" "editor" {
  name                          = "editor-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.editor.id
  enabled                       = true
  host_name                     = azurerm_container_app.editor.latest_revision_fqdn
  http_port                     = 80
  https_port                    = 443
  origin_host_header            = azurerm_container_app.editor.latest_revision_fqdn
  certificate_name_check_enabled = true

  private_link {
    request_message        = "Front Door to n8n editor"
    target_type            = "managedEnvironments"
    location               = var.location
    private_link_target_id = azurerm_container_app_environment.env.id
  }
}

resource "azurerm_cdn_frontdoor_origin" "webhook" {
  name                          = "webhook-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.webhook.id
  enabled                       = true
  host_name                     = azurerm_container_app.webhook.latest_revision_fqdn
  http_port                     = 80
  https_port                    = 443
  origin_host_header            = azurerm_container_app.webhook.latest_revision_fqdn
  certificate_name_check_enabled = true

  private_link {
    request_message        = "Front Door to n8n webhook"
    target_type            = "managedEnvironments"
    location               = var.location
    private_link_target_id = azurerm_container_app_environment.env.id
  }
}

resource "azurerm_cdn_frontdoor_route" "webhook" {
  name                          = "webhook-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.fd_endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.webhook.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.webhook.id]
  enabled                       = true
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  patterns_to_match             = ["/webhook", "/webhook/*"]
  supported_protocols           = ["Http", "Https"]
  link_to_default_domain        = true
}

resource "azurerm_cdn_frontdoor_route" "editor" {
  name                          = "editor-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.fd_endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.editor.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.editor.id]
  enabled                       = true
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  patterns_to_match             = ["/*"]
  supported_protocols           = ["Http", "Https"]
  link_to_default_domain        = true
}
