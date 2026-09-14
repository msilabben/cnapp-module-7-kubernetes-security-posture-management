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
    owner       = "oivind@mnemonic.no"
  }
}

variable "acr_name_prefix" {
  description = "Prefix for the Azure Container Registry name. A random suffix is appended to keep it globally unique."
  type        = string
  default     = "module7akslab"
}

variable "labtarget_node_vm_size" {
  description = "VM size for the shared node pool used by the pod-security lab. Handles about 15 participant pods comfortably."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "labtarget_node_count" {
  description = "Number of nodes in the lab-target node pool. Keep this at 1 - every participant must land on the same node so they can reach each other's secrets through the node's disk."
  type        = number
  default     = 1

  validation {
    condition     = var.labtarget_node_count >= 1
    error_message = "labtarget_node_count must be at least 1."
  }
}
