#!/usr/bin/env bash
# Build the lab image in the ACR, and pin its name into the pod manifests.
# Run after `az aks get-credentials` (see the root README). Safe to re-run
# any time the image needs rebuilding (e.g. if the registry gets wiped).
#
# No Terraform dependency on purpose: this needs to run from wherever you
# have az/kubectl access (Cloud Shell, Codespaces, ...), which usually has
# no local Terraform state. Values are fixed defaults from
# terraform/variables.tf and outputs.tf, override with env vars if you
# changed them.
#
# Usage: ./scripts/build-image.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ACR_NAME="${ACR_NAME:-module7akslab967a44}"
ACR_LOGIN_SERVER="${ACR_LOGIN_SERVER:-module7akslab967a44.azurecr.io}"
IMAGE="${ACR_LOGIN_SERVER}/module-7-lab:1"

echo "==> Building ${IMAGE} in ${ACR_NAME}"
az acr build --registry "$ACR_NAME" --image module-7-lab:1 .

for f in manifests/insecure-pod.yaml manifests/hardened-pod.yaml manifests/east-west/frontend-pod.yaml manifests/east-west/database.yaml manifests/north-south/shop-pod.yaml; do
  sed -i.bak "s|__IMAGE__|${IMAGE}|g" "$f"
  rm -f "${f}.bak"
  echo "  set image in $f -> ${IMAGE}"
done

echo
echo "Done. Commit the manifests so participants can 'kubectl apply -f' them directly."
