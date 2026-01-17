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
resource "kubernetes_namespace" "argocd" {
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
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "9.3.4"

  set = [{
    name  = "server.service.type"
    value = "LoadBalancer"
  }]

  depends_on = [kubernetes_namespace.argocd]
}
