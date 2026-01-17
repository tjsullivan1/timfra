output "disk_id" {
  description = "ID of the managed disk"
  value       = azurerm_managed_disk.postgres.id
}

output "disk_name" {
  description = "Name of the managed disk"
  value       = azurerm_managed_disk.postgres.name
}
