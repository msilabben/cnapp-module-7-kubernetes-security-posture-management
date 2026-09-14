#!/usr/bin/env bash
# Build the lab image in the Terraform-managed ACR, and pin its name into the
# pod manifests. Run once, after `terraform apply` and after `az aks
# get-credentials` (see the root README).
#
# Usage: ./scripts/build-image.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ACR_NAME=$(terraform -chdir=terraform output -raw acr_name)
ACR_LOGIN_SERVER=$(terraform -chdir=terraform output -raw acr_login_server)
IMAGE="${ACR_LOGIN_SERVER}/skatteetaten-lab:1"

echo "==> Building ${IMAGE} in ${ACR_NAME}"
az acr build --registry "$ACR_NAME" --image skatteetaten-lab:1 .

for f in manifests/insecure-pod.yaml manifests/hardened-pod.yaml manifests/east-west/frontend-pod.yaml manifests/east-west/database.yaml; do
  sed -i.bak "s|__IMAGE__|${IMAGE}|g" "$f"
  rm -f "${f}.bak"
  echo "  set image in $f -> ${IMAGE}"
done

echo
echo "Done. Commit the manifests so participants can 'kubectl apply -f' them directly."
