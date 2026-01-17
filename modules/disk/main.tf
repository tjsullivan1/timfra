resource "azurerm_managed_disk" "postgres" {
  name                 = "disk-${var.prefix}-postgres"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = "PremiumV2_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.disk_size_gb
  disk_iops_read_write = var.disk_iops_read_write
  disk_mbps_read_write = var.disk_mbps_read_write
  zone                 = var.availability_zone

  tags = var.tags
}
