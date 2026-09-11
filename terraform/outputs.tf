output "resource_group_name" {
  description = "Name of the resource group containing the AKS cluster."
  value       = azurerm_resource_group.aks.name
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.aks.name
}

output "cluster_id" {
  description = "Azure resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.aks.id
}

output "kubernetes_version" {
  description = "Kubernetes version selected by AKS."
  value       = azurerm_kubernetes_cluster.aks.current_kubernetes_version
}

output "acr_name" {
  description = "Name of the Azure Container Registry used to build the lab image."
  value       = azurerm_container_registry.lab.name
}

output "acr_login_server" {
  description = "Login server of the Azure Container Registry, used as the image prefix."
  value       = azurerm_container_registry.lab.login_server
}
