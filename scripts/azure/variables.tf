variable "resource_group_name" {
  description = "Value of the resource group name"
  type        = string
  default     = "cle-rg"
}

variable "location" {
  description = "Value of the location"
  type        = string
  default     = "East US"
}

variable "vm_sku" {
  description = "Value of the VM SKU"
  type        = string
  default     = "Standard_D2ds_v5"
}