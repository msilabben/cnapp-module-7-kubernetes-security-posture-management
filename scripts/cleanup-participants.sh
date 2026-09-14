#!/usr/bin/env bash
# Deletes every participant namespace (s01, s02, ...) and the local
# kubeconfigs in ./out/. The opposite of 03-participants.sh.
#
# The cluster, ACR and lab image are untouched - safe to run between test
# rounds, then re-run 03-participants.sh to start fresh.
#
# Usage: ./scripts/cleanup-participants.sh
set -euo pipefail
cd "$(dirname "$0")/.."

NAMESPACES=$(kubectl get ns -o name | grep -E '^namespace/s[0-9]+$' | sed 's#namespace/##' || true)

if [[ -z "$NAMESPACES" ]]; then
  echo "No participant namespaces found."
else
  echo "Deleting namespaces: $NAMESPACES"
  # shellcheck disable=SC2086
  kubectl delete namespace $NAMESPACES
fi

rm -rf out/
echo "Removed ./out/ (kubeconfigs)."
