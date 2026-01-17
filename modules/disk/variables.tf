variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "disk_size_gb" {
  description = "Size of the managed disk in GB"
  type        = number
  default     = 32
}

variable "disk_iops_read_write" {
  description = "IOPS for the disk"
  type        = number
  default     = 3000
}

variable "disk_mbps_read_write" {
  description = "MBps throughput for the disk"
  type        = number
  default     = 125
}

variable "availability_zone" {
  description = "Availability zone for the disk"
  type        = string
  default     = "1"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
