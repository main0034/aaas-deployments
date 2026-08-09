###############################################################################
# Generated deployment stub.
#
# This file is boilerplate and should not need editing. All variation between
# deployments lives in terraform.tfvars.json, which is the only file the agent
# writes and the only file CI validates against a schema.
#
# The module source uses HTTPS. Because aaas-infra-modules is private, CI
# rewrites github.com URLs to inject a short-lived GitHub App token before
# running `terraform init` (see .github/workflows/plan.yml).
#
# Bump `ref` deliberately to adopt a new module version.
###############################################################################

terraform {
  required_version = "~> 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.20"
    }
  }

  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
  }
}

provider "azurerm" {
  use_oidc = true

  # By default the provider tries to register every resource provider it
  # supports - roughly a hundred of them, including things this stack will
  # never touch. The plan identity is deliberately Reader-only, so those
  # attempts fail with 403 and abort the run.
  #
  # bootstrap.sh registers the specific providers this module needs, which is
  # both the least-privilege answer and the faster one. If a future module
  # adds a resource type, register its provider there rather than widening
  # these credentials.
  resource_provider_registrations = "none"

  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

module "app" {
  source = "git::https://github.com/main0034/aaas-infra-modules.git//modules/app-stack?ref=v0.1.1"

  name            = var.name
  environment     = var.environment
  location        = var.location
  container_image = var.container_image
  container_port  = var.container_port

  cpu          = var.cpu
  memory       = var.memory
  min_replicas = var.min_replicas
  max_replicas = var.max_replicas
  app_env      = var.app_env

  postgres_sku                   = var.postgres_sku
  postgres_storage_mb            = var.postgres_storage_mb
  postgres_version               = var.postgres_version
  database_name                  = var.database_name
  postgres_backup_retention_days = var.postgres_backup_retention_days

  registry_server   = var.registry_server
  registry_username = var.registry_username
  registry_password = var.registry_password

  vnet_address_space = var.vnet_address_space
  tags               = var.tags
}

output "app_url" {
  value = module.app.app_url
}

output "postgres_fqdn" {
  value = module.app.postgres_fqdn
}

output "resource_group_name" {
  value = module.app.resource_group_name
}
