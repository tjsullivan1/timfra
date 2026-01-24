locals {
  environment = "dev"
  common_tags = merge(var.tags, {
    Project = var.prefix
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.prefix}-${local.environment}"
  location = var.location
  tags     = local.common_tags
}

# Network Module
module "network" {
  source = "../../modules/network"

  prefix                    = var.prefix
  location                  = var.location
  resource_group_name       = azurerm_resource_group.main.name
  vnet_address_space        = var.vnet_address_space
  aks_subnet_address_prefix = var.aks_subnet_address_prefix
  db_subnet_address_prefix  = var.db_subnet_address_prefix
  tags                      = local.common_tags
}

# AKS Module
module "aks" {
  source = "../../modules/aks"

  prefix                         = var.prefix
  location                       = var.location
  resource_group_name            = azurerm_resource_group.main.name
  vnet_subnet_id                 = module.network.aks_subnet_id
  kubernetes_version             = var.kubernetes_version
  default_node_pool_vm_size      = var.default_node_pool_vm_size
  default_node_pool_node_count   = var.default_node_pool_node_count
  tags                           = local.common_tags
}

# Disk Module
module "disk" {
  source = "../../modules/disk"

  prefix              = var.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  disk_size_gb        = var.disk_size_gb
  tags                = local.common_tags
}

# Kubernetes Namespace for ArgoCD
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [module.aks]
}

# Helm Release for ArgoCD
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  version    = "9.3.4"

  set = [{
    name  = "server.service.type"
    value = "LoadBalancer"
  }]

  depends_on = [kubernetes_namespace_v1.argocd]
}

resource "azurerm_storage_account" "backup_store" {
  name                     = "st${var.prefix}backup"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
} 

resource "azurerm_storage_container" "backups" {
  name                 = "backups"
  storage_account_id   = azurerm_storage_account.backup_store.id
  container_access_type = "private"
}

# 1. Create the Identity for Postgres
resource "azurerm_user_assigned_identity" "pg_backup_identity" {
  name                = "${var.prefix}-pg-backup-id"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

# 2. Grant it access to the Storage Account
resource "azurerm_role_assignment" "storage_contributor" {
  scope                = azurerm_storage_account.backup_store.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.pg_backup_identity.principal_id
}

# 3. Federated Credential (the "Link" to AKS)
resource "azurerm_federated_identity_credential" "pg_backup_fed" {
  name                = "pg-backup-fed-credential"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.pg_backup_identity.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:database-dev:tim-db" # Match your DB name/ns
}

resource "azurerm_federated_identity_credential" "eso_federation" {
  name                = "eso-federation"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.aks.identity_principal_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:external-secrets:external-secrets" # Match your DB name/ns
}

# Create the namespace so it exists for the ConfigMap and ServiceAccount
resource "kubernetes_namespace" "db_dev" {
  metadata {
    name = "database-dev"
  }
}

# 4. Inject variables into K8s so Argo CD can see them
resource "kubernetes_config_map_v1" "infra_outputs" {
  metadata {
    name      = "infra-outputs"
    namespace = kubernetes_namespace.db_dev.metadata[0].name
  }
  data = {
    storage_account_name = azurerm_storage_account.backup_store.name
    container_name       = azurerm_storage_container.backups.name
    client_id            = azurerm_user_assigned_identity.pg_backup_identity.client_id
  }
}

# Get current client configuration for the deploying service principal
data "azurerm_client_config" "current" {}

# Azure Key Vault with RBAC enabled
resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.prefix}-${local.environment}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  tags = local.common_tags
}

# Role assignment: Deploying service principal - Key Vault Secrets Officer (read/write)
resource "azurerm_role_assignment" "kv_deployer_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Role assignment: AKS managed identity - Key Vault Secrets User (read)
resource "azurerm_role_assignment" "kv_aks_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.aks.identity_principal_id
}

# Role assignment: Admin user - Key Vault Secrets User (read)
resource "azurerm_role_assignment" "kv_user_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.keyvault_admin_user_object_id
}

# Secret: Storage account name
resource "azurerm_key_vault_secret" "storage_account_name" {
  name         = "timstapaper-storage-account-name"
  value        = azurerm_storage_account.backup_store.name
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.kv_deployer_secrets_officer]
}