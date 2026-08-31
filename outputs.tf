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
