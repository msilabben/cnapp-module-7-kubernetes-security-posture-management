resource "azurerm_resource_group" "aks" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = var.cluster_name

  default_node_pool {
    name       = "system"
    node_count = var.node_count
    vm_size    = var.node_vm_size
  }

  identity {
    type = "SystemAssigned"
  }

  # Calico enforces NetworkPolicy (tasks/east_west.md). network_plugin and
  # network_plugin_mode match what the cluster already runs - only
  # network_policy is actually changing.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "calico"
  }

  tags = var.tags
}

# Shared node pool for the pod-security lab (tasks/pod_security.md). One node,
# labelled so the lab's manifests can target it with nodeSelector: lab=target -
# every participant needs to land on the same node.
resource "azurerm_kubernetes_cluster_node_pool" "labtarget" {
  name                  = "labtarget"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.labtarget_node_vm_size
  node_count            = var.labtarget_node_count
  mode                  = "User"

  node_labels = {
    lab = "target"
  }

  tags = var.tags
}

resource "random_id" "acr_suffix" {
  byte_length = 3
}

resource "azurerm_container_registry" "lab" {
  name                = "${var.acr_name_prefix}${random_id.acr_suffix.hex}"
  resource_group_name = azurerm_resource_group.aks.name
  location            = azurerm_resource_group.aks.location
  sku                 = "Basic"

  tags = var.tags
}

# Lets AKS pull images from the registry without a separate pull secret.
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.lab.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}
