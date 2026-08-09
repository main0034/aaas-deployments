###############################################################################
# Pass-through variable declarations.
#
# Boilerplate. Values come from terraform.tfvars.json; constraints and
# validation live in the module. Deliberately no defaults duplicated here
# beyond what Terraform needs to make them optional - the module owns the
# real defaults, so there is exactly one place to change them.
###############################################################################

variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "location" {
  type    = string
  default = "swedencentral"
}

variable "container_image" {
  type = string
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "cpu" {
  type    = number
  default = 0.25
}

variable "memory" {
  type    = string
  default = "0.5Gi"
}

variable "min_replicas" {
  type    = number
  default = 0
}

variable "max_replicas" {
  type    = number
  default = 2
}

variable "app_env" {
  type    = map(string)
  default = {}
}

variable "postgres_sku" {
  type    = string
  default = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  type    = number
  default = 32768
}

variable "postgres_version" {
  type    = string
  default = "16"
}

variable "database_name" {
  type    = string
  default = "appdb"
}

variable "postgres_backup_retention_days" {
  type    = number
  default = 7
}

variable "registry_server" {
  type    = string
  default = "ghcr.io"
}

variable "registry_username" {
  type    = string
  default = ""
}

# Supplied by CI via TF_VAR_registry_password, never written to the repo.
variable "registry_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "vnet_address_space" {
  type    = string
  default = "10.60.0.0/16"
}

variable "tags" {
  type = map(string)
}
