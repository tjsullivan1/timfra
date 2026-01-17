# AKS Terraform Platform

A comprehensive Terraform platform for deploying Azure Kubernetes Service (AKS) with proper networking, storage, and GitOps tooling.

## Architecture Overview

This platform provides:

- **Virtual Network**: Dedicated VNet with separate subnets for AKS and database workloads
- **AKS Cluster**: Managed Kubernetes cluster with:
  - User-Assigned Managed Identity
  - OIDC Workload Identity enabled
  - Azure CNI Overlay networking
  - Auto-scaling node pools
- **Premium Storage**: Premium SSD v2 managed disk for PostgreSQL persistence
- **GitOps Ready**: ArgoCD pre-installed in dedicated namespace

## Repository Structure

```
.
├── modules/
│   ├── network/          # VNET and subnet configuration
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── aks/              # AKS cluster with OIDC and CNI Overlay
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── disk/             # Premium SSD v2 managed disk
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── environments/
    └── dev/              # Development environment
        ├── main.tf
        ├── variables.tf
        ├── providers.tf
        ├── outputs.tf
        └── terraform.tfvars.example
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.12.0
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.30.0
- Azure subscription with appropriate permissions
- Azure AD tenant ID
- For OIDC authentication: Configured federated identity credentials in Azure AD

## Quick Start

### 1. Configure Authentication

This platform uses OIDC authentication (no secrets required). Ensure your Azure AD application has federated credentials configured for your deployment environment (e.g., GitHub Actions, Azure DevOps).

### 2. Prepare Variables

```bash
cd environments/dev
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
prefix          = "myproject"
location        = "canadacentral"
tenant_id       = "your-tenant-id"
subscription_id = "your-subscription-id"
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### 4. Access Your Cluster

```bash
# Get AKS credentials
az aks get-credentials --resource-group <resource-group-name> --name <cluster-name>

# Verify cluster access
kubectl get nodes

# Check ArgoCD installation
kubectl get pods -n argocd
```

### 5. Access ArgoCD UI

```bash
# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access ArgoCD at https://localhost:8080
# Username: admin
# Password: (from command above)
```

## Module Details

### Network Module

Creates a Virtual Network with two subnets:

- **AKS Subnet**: For AKS cluster nodes and pods
- **Database Subnet**: Delegated for Azure PostgreSQL Flexible Server with proper service delegation

**Inputs:**
- `prefix`: Resource name prefix
- `location`: Azure region
- `resource_group_name`: Resource group name
- `vnet_address_space`: VNet CIDR (default: `["10.0.0.0/16"]`)
- `aks_subnet_address_prefix`: AKS subnet CIDR (default: `"10.0.1.0/24"`)
- `db_subnet_address_prefix`: DB subnet CIDR (default: `"10.0.2.0/24"`)

**Outputs:**
- `vnet_id`: Virtual Network ID
- `aks_subnet_id`: AKS subnet ID
- `db_subnet_id`: Database subnet ID

### AKS Module

Deploys an AKS cluster with:

- User-Assigned Managed Identity
- OIDC issuer enabled for workload identity
- Azure CNI with Overlay mode
- Auto-scaling enabled on default node pool

**Inputs:**
- `prefix`: Resource name prefix
- `location`: Azure region
- `resource_group_name`: Resource group name
- `vnet_subnet_id`: Subnet ID for AKS nodes
- `kubernetes_version`: K8s version (default: `"1.28"`)
- `default_node_pool_vm_size`: VM size (default: `"Standard_D2s_v3"`)
- `default_node_pool_node_count`: Initial node count (default: `2`)

**Outputs:**
- `cluster_name`: AKS cluster name
- `cluster_id`: AKS cluster ID
- `oidc_issuer_url`: OIDC issuer URL for workload identity
- `kube_config`: Kubernetes configuration (sensitive)

### Disk Module

Creates a Premium SSD v2 managed disk for PostgreSQL data persistence.

**Inputs:**
- `prefix`: Resource name prefix
- `location`: Azure region
- `resource_group_name`: Resource group name
- `disk_size_gb`: Disk size in GB (default: `32`)
- `disk_iops_read_write`: IOPS limit (default: `3000`)
- `disk_mbps_read_write`: Throughput in MBps (default: `125`)

**Outputs:**
- `disk_id`: Managed disk ID
- `disk_name`: Managed disk name

## Configuration Details

### Provider Configuration

The `providers.tf` is configured for OIDC authentication with no secrets:

```hcl
provider "azurerm" {
  features {}
  use_oidc        = true
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}
```

Kubernetes and Helm providers automatically authenticate using AKS credentials.

### Network Architecture

- **VNet**: `10.0.0.0/16` (configurable)
- **AKS Subnet**: `10.0.1.0/24` - For Kubernetes nodes
- **DB Subnet**: `10.0.2.0/24` - Delegated for PostgreSQL Flexible Server
- **Service CIDR**: `10.1.0.0/16` - For Kubernetes services (overlay)
- **DNS Service IP**: `10.1.0.10` - CoreDNS service IP

### AKS Configuration

- **Network Plugin**: Azure CNI
- **Network Plugin Mode**: Overlay (no IP exhaustion)
- **Network Policy**: Azure Network Policy
- **Identity**: User-Assigned Managed Identity
- **OIDC**: Enabled for workload identity federation
- **Auto-scaling**: Enabled (min: 1, max: 3 nodes)

## Customization

### Changing Node Pool Configuration

Edit `environments/dev/variables.tf` or override in `terraform.tfvars`:

```hcl
default_node_pool_vm_size    = "Standard_D4s_v3"
default_node_pool_node_count = 3
```

### Adding Additional Node Pools

Add to `environments/dev/main.tf`:

```hcl
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = module.aks.cluster_id
  vm_size               = "Standard_D4s_v3"
  node_count            = 2
  vnet_subnet_id        = module.network.aks_subnet_id
}
```

### Changing Disk Performance

Modify disk parameters in `terraform.tfvars`:

```hcl
disk_size_gb = 64
```

For higher IOPS/throughput, update module call in `main.tf`:

```hcl
module "disk" {
  # ...
  disk_iops_read_write = 5000
  disk_mbps_read_write = 200
}
```

## Using the Managed Disk with PostgreSQL

The Premium SSD v2 disk can be attached to a PostgreSQL pod using a PersistentVolume:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgres-pv
spec:
  capacity:
    storage: 32Gi
  accessModes:
    - ReadWriteOnce
  azureDisk:
    diskName: <disk-name-from-output>
    diskURI: <disk-id-from-output>
    kind: Managed
```

## ArgoCD Setup

ArgoCD is automatically installed in the `argocd` namespace with:

- Server exposed via LoadBalancer
- Latest stable version (7.7.11)

### Post-Deployment ArgoCD Configuration

1. **Change Admin Password:**
   ```bash
   kubectl -n argocd patch secret argocd-secret \
     -p '{"stringData": {"admin.password": "'$(htpasswd -bnBC 10 "" <password> | tr -d ':\n')'"}}'
   ```

2. **Configure Git Repository:**
   ```bash
   argocd repo add https://github.com/your-org/your-repo \
     --username <username> \
     --password <password>
   ```

3. **Create Application:**
   ```bash
   argocd app create myapp \
     --repo https://github.com/your-org/your-repo \
     --path manifests \
     --dest-server https://kubernetes.default.svc \
     --dest-namespace default
   ```

## Security Considerations

- **OIDC Authentication**: No secrets stored in code
- **Managed Identity**: AKS uses managed identity for Azure resource access
- **Network Isolation**: Separate subnets for workload types
- **RBAC**: Kubernetes RBAC enabled by default
- **Workload Identity**: OIDC issuer enabled for pod-level identity

## Maintenance

### Updating Kubernetes Version

```bash
# Check available versions
az aks get-versions --location canadacentral

# Update terraform.tfvars
kubernetes_version = "1.29"

# Apply update
terraform apply
```

### Scaling Node Pool

```bash
# Via Terraform
default_node_pool_node_count = 4

# Or via Azure CLI
az aks scale --resource-group <rg-name> --name <cluster-name> --node-count 4
```

## Troubleshooting

### Provider Authentication Issues

Ensure your OIDC token has the correct audience and that federated credentials are configured in Azure AD.

### AKS Provisioning Failures

Check that:
- Subscription has sufficient quota for VM SKU
- VNet has available IP addresses
- Service principal/managed identity has correct permissions

### ArgoCD Not Accessible

```bash
# Check pod status
kubectl get pods -n argocd

# Check service
kubectl get svc -n argocd

# Check for LoadBalancer IP assignment
kubectl get svc argocd-server -n argocd
```

## Clean Up

```bash
# Destroy all resources
terraform destroy
```

⚠️ **Warning**: This will delete all resources including the AKS cluster and managed disk.

## Contributing

1. Create a feature branch
2. Make your changes
3. Run `terraform fmt -recursive`
4. Run `terraform validate`
5. Submit a pull request

## License

See [LICENSE](../../LICENSE) file for details.

## Support

For issues and questions, please open an issue in the repository.
