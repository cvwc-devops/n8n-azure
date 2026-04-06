variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "name_prefix" {
  type        = string
  description = "Prefix used for resource names"
}

variable "key_vault_name" {
  type        = string
  description = "Existing Key Vault name containing n8n secrets"
}

variable "n8n_host" {
  type        = string
  description = "Public HTTPS hostname for n8n, for example n8n.example.com"
}

variable "n8n_image" {
  type        = string
  description = "Container image"
  default     = "docker.n8n.io/n8nio/n8n:1.87.2"
}

variable "container_cpu" {
  type        = number
  default     = 1
}

variable "container_memory" {
  type        = string
  default     = "2Gi"
}

variable "postgres_sku_name" {
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_version" {
  type        = string
  default     = "16"
}

variable "postgres_storage_mb" {
  type        = number
  default     = 32768
}

variable "db_name" {
  type        = string
  default     = "n8n"
}

variable "db_admin_user" {
  type        = string
  default     = "n8nadmin"
}

variable "tags" {
  type        = map(string)
  default     = {}
}
