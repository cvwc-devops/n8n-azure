variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "key_vault_name" { type = string }
variable "key_vault_resource_group_name" { type = string, default = null }
variable "prefix" { type = string }
variable "tags" { type = map(string), default = {} }
variable "container_app_env_cidr" { type = string, default = "10.40.0.0/23" }
variable "infra_subnet_cidr" { type = string, default = "10.40.2.0/27" }
variable "postgres_admin_username" { type = string, default = "n8nadmin" }
variable "postgres_sku_name" { type = string, default = "B_Standard_B1ms" }
variable "postgres_storage_mb" { type = number, default = 32768 }
variable "redis_sku_name" { type = string, default = "Basic" }
variable "redis_family" { type = string, default = "C" }
variable "redis_capacity" { type = number, default = 1 }
variable "n8n_image" { type = string, default = "docker.n8n.io/n8nio/n8n:latest" }
variable "editor_min_replicas" { type = number, default = 1 }
variable "editor_max_replicas" { type = number, default = 2 }
variable "webhook_min_replicas" { type = number, default = 1 }
variable "webhook_max_replicas" { type = number, default = 5 }
variable "worker_min_replicas" { type = number, default = 1 }
variable "worker_max_replicas" { type = number, default = 5 }
variable "worker_concurrency" { type = number, default = 5 }
variable "frontdoor_custom_domain" { type = string, default = "" }
variable "webhook_base_url" { type = string, default = "" }
