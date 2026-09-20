#!/usr/bin/env bash
# One-time cluster setup for tasks/north_south.md.
#
# CLI-only: the azurerm Terraform provider does not yet support
# --enable-gateway-api (open upstream issue). Both commands below are purely
# additive - they install the Istio add-on and the Gateway API CRDs, and do
# not touch NetworkPolicy, node pools, RBAC, or any existing namespace, so
# they're safe to run without affecting pod_security.md or east_west.md.
#
# No Terraform dependency on purpose: this needs to run from wherever you
# have kubectl/az access (Cloud Shell, Codespaces, ...), which usually has
# no local Terraform state. Resource group and cluster name are fixed
# defaults from terraform/variables.tf, override with env vars if you
# changed them.
#
# Usage: ./scripts/enable-gateway-api.sh
set -euo pipefail
cd "$(dirname "$0")/.."

RG="${RG:-module-7-aks-rg}"
CLUSTER="${CLUSTER:-module-7-aks}"

echo "==> Enabling the Istio service mesh add-on"
az aks mesh enable --resource-group "$RG" --name "$CLUSTER"

echo "==> Installing the Kubernetes Gateway API CRDs"
az aks update --resource-group "$RG" --name "$CLUSTER" --enable-gateway-api

echo
echo "Done. Verify with:"
echo "  kubectl get crds | grep gateway.networking.k8s.io"
