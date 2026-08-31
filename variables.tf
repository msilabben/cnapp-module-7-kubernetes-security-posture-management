variable "resource_group_name" {
  description = "Name of the Azure resource group that contains the AKS cluster."
  type        = string
  default     = "module-7-aks-rg"
}

variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
  default     = "module-7-aks"
}

variable "location" {
  description = "Azure region in which to deploy the resources."
  type        = string
  default     = "Norway East"
}

variable "node_count" {
  description = "Number of nodes in the default node pool."
  type        = number
  default     = 1

  validation {
    condition     = var.node_count >= 1
    error_message = "node_count must be at least 1."
  }
}

variable "node_vm_size" {
  description = "Azure VM size used by the default node pool."
  type        = string
  default     = "Standard_D2_v2"
}

variable "tags" {
  description = "Tags applied to the resource group and AKS cluster."
  type        = map(string)
  default = {
    environment = "lab"
    managed-by  = "terraform"
  }
}
