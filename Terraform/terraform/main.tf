locals {
  prefix_clean        = lower(replace(var.name_prefix, "-", ""))
  postgres_server     = substr("${local.prefix_clean}pg${random_string.suffix.result}", 0, 60)
  containerapp_env    = "${var.name_prefix}-cae"
  containerapp_name   = "${var.name_prefix}-n8n"
  log_analytics_name  = "${var.name_prefix}-law"
  db_fqdn             = azurerm_postgresql_flexible_server.this.fqdn
  db_port             = 5432
  webhook_url         = "https://${var.n8n_host}/"
}

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

data "azurerm_client_config" "current" {}

data "azurerm_key_vault" "this" {
  name                = var.key_vault_name
  resource_group_name = azurerm_resource_group.this.name
}

data "azurerm_key_vault_secret" "db_password" {
  name         = "n8n-db-password"
  key_vault_id = data.azurerm_key_vault.this.id
}

data "azurerm_key_vault_secret" "encryption_key" {
  name         = "n8n-encryption-key"
  key_vault_id = data.azurerm_key_vault.this.id
}

data "azurerm_key_vault_secret" "jwt_secret" {
  name         = "n8n-user-management-jwt-secret"
  key_vault_id = data.azurerm_key_vault.this.id
}

data "azurerm_key_vault_secret" "basic_auth_user" {
  name         = "n8n-basic-auth-user"
  key_vault_id = data.azurerm_key_vault.this.id
}

data "azurerm_key_vault_secret" "basic_auth_password" {
  name         = "n8n-basic-auth-password"
  key_vault_id = data.azurerm_key_vault.this.id
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = local.log_analytics_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_container_app_environment" "this" {
  name                       = local.containerapp_env
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  tags                       = var.tags
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                          = local.postgres_server
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  version                       = var.postgres_version
  delegated_subnet_id           = null
  public_network_access_enabled = true
  administrator_login           = var.db_admin_user
  administrator_password        = data.azurerm_key_vault_secret.db_password.value
  zone                          = "1"
  storage_mb                    = var.postgres_storage_mb
  sku_name                      = var.postgres_sku_name
  backup_retention_days         = 7
  tags                          = var.tags
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_container_app" "this" {
  name                         = local.containerapp_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type = "SystemAssigned"
  }

  secret {
    name                = "db-password"
    identity            = "system"
    key_vault_secret_id = data.azurerm_key_vault_secret.db_password.versionless_id
  }

  secret {
    name                = "n8n-encryption-key"
    identity            = "system"
    key_vault_secret_id = data.azurerm_key_vault_secret.encryption_key.versionless_id
  }

  secret {
    name                = "n8n-jwt-secret"
    identity            = "system"
    key_vault_secret_id = data.azurerm_key_vault_secret.jwt_secret.versionless_id
  }

  secret {
    name                = "n8n-basic-auth-user"
    identity            = "system"
    key_vault_secret_id = data.azurerm_key_vault_secret.basic_auth_user.versionless_id
  }

  secret {
    name                = "n8n-basic-auth-password"
    identity            = "system"
    key_vault_secret_id = data.azurerm_key_vault_secret.basic_auth_password.versionless_id
  }

  ingress {
    external_enabled = true
    target_port      = 5678
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "n8n"
      image  = var.n8n_image
      cpu    = var.container_cpu
      memory = var.container_memory

      env {
        name  = "DB_TYPE"
        value = "postgresdb"
      }
      env {
        name  = "DB_POSTGRESDB_HOST"
        value = local.db_fqdn
      }
      env {
        name  = "DB_POSTGRESDB_PORT"
        value = tostring(local.db_port)
      }
      env {
        name  = "DB_POSTGRESDB_DATABASE"
        value = azurerm_postgresql_flexible_server_database.this.name
      }
      env {
        name  = "DB_POSTGRESDB_USER"
        value = "${var.db_admin_user}"
      }
      env {
        name        = "DB_POSTGRESDB_PASSWORD"
        secret_name = "db-password"
      }
      env {
        name  = "N8N_HOST"
        value = var.n8n_host
      }
      env {
        name  = "N8N_PROTOCOL"
        value = "https"
      }
      env {
        name  = "N8N_PORT"
        value = "5678"
      }
      env {
        name  = "WEBHOOK_URL"
        value = local.webhook_url
      }
      env {
        name  = "N8N_PROXY_HOPS"
        value = "1"
      }
      env {
        name  = "N8N_EDITOR_BASE_URL"
        value = "https://${var.n8n_host}/"
      }
      env {
        name  = "GENERIC_TIMEZONE"
        value = "Europe/Dublin"
      }
      env {
        name  = "TZ"
        value = "Europe/Dublin"
      }
      env {
        name  = "N8N_DIAGNOSTICS_ENABLED"
        value = "false"
      }
      env {
        name  = "N8N_SECURE_COOKIE"
        value = "true"
      }
      env {
        name  = "N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS"
        value = "true"
      }
      env {
        name        = "N8N_ENCRYPTION_KEY"
        secret_name = "n8n-encryption-key"
      }
      env {
        name        = "N8N_USER_MANAGEMENT_JWT_SECRET"
        secret_name = "n8n-jwt-secret"
      }
      env {
        name  = "N8N_BASIC_AUTH_ACTIVE"
        value = "true"
      }
      env {
        name        = "N8N_BASIC_AUTH_USER"
        secret_name = "n8n-basic-auth-user"
      }
      env {
        name        = "N8N_BASIC_AUTH_PASSWORD"
        secret_name = "n8n-basic-auth-password"
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.keyvault_secrets_user
  ]
}

resource "azurerm_role_assignment" "keyvault_secrets_user" {
  scope                = data.azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_app.this.identity[0].principal_id
}
