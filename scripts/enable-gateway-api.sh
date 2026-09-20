#!/usr/bin/env bash
# One-time cluster setup for tasks/north_south.md.
#
# CLI-only: the azurerm Terraform provider does not yet support
# --enable-gateway-api (open upstream issue). Both commands below are purely
# additive - they install the Istio add-on and the Gateway API CRDs, and do
# not touch NetworkPolicy, node pools, RBAC, or any existing namespace, so
# they're safe to run without affecting pod_security.md or east_west.md.
#
# Usage: ./scripts/enable-gateway-api.sh
set -euo pipefail
cd "$(dirname "$0")/.."

RG=$(terraform -chdir=terraform output -raw resource_group_name)
CLUSTER=$(terraform -chdir=terraform output -raw cluster_name)

echo "==> Enabling the Istio service mesh add-on"
az aks mesh enable --resource-group "$RG" --name "$CLUSTER"

echo "==> Installing the Kubernetes Gateway API CRDs"
az aks update --resource-group "$RG" --name "$CLUSTER" --enable-gateway-api

echo
echo "Done. Verify with:"
echo "  kubectl get crds | grep gateway.networking.k8s.io"
