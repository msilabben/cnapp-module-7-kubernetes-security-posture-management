#!/usr/bin/env bash
# One namespace + flag secret + service accounts + RBAC + kubeconfig per
# participant, written to ./out/ (gitignored).
#
#   sa/student - the human. Can manage pods, CANNOT read secrets.
#   sa/app     - the pod.   CAN read secrets in its own namespace.
#
# That split is why `kubectl get secrets` is Forbidden for participants, and
# the only way to a flag is through the pod - see tasks/pod_security.md.
#
# Usage: ./scripts/03-participants.sh [participant-count]   (default: 5)
# The real session runs 20 participants: ./scripts/03-participants.sh 20
# Safe to re-run: existing namespaces/secrets/accounts are just re-applied.
set -euo pipefail
cd "$(dirname "$0")/.."

PARTICIPANTS="${1:-5}"
mkdir -p out

SERVER=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# Read-only node access for tasks/north_south.md step 1 (comparing node IPs
# to pod IPs). nodes are cluster-scoped, a namespaced Role can never grant
# access to them, so this is one shared ClusterRole/ClusterRoleBinding
# covering every participant's service account via the built-in
# system:serviceaccounts group, applied once, not per participant.
kubectl apply -f - -o name >/dev/null << YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: { name: node-reader }
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: node-reader }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: node-reader }
subjects:
  - kind: Group
    name: system:serviceaccounts
    apiGroup: rbac.authorization.k8s.io
YAML

for i in $(seq -f "%02g" 1 "$PARTICIPANTS"); do
  NS="s${i}"
  echo "==> $NS"

  kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - -o name >/dev/null

  FLAG="LAB-FLAG-${NS}-$(openssl rand -hex 4)"
  kubectl -n "$NS" create secret generic flag \
    --from-literal=flag.txt="$FLAG" \
    --dry-run=client -o yaml | kubectl apply -f - -o name >/dev/null

  kubectl apply -f - -o name >/dev/null << YAML
apiVersion: v1
kind: ServiceAccount
metadata: { name: app, namespace: ${NS} }
---
apiVersion: v1
kind: ServiceAccount
metadata: { name: student, namespace: ${NS} }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: app, namespace: ${NS} }
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: app, namespace: ${NS} }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: Role, name: app }
subjects:
  - { kind: ServiceAccount, name: app, namespace: ${NS} }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: student, namespace: ${NS} }
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch", "create", "delete", "patch"]
  - apiGroups: [""]
    resources: ["pods/exec", "pods/attach", "pods/portforward"]
    verbs: ["create", "get"]
  - apiGroups: [""]
    resources: ["pods/log", "events", "serviceaccounts"]
    verbs: ["get", "list"]
  # Needed for tasks/east_west.md
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list", "watch", "create", "delete", "patch"]
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["networkpolicies"]
    verbs: ["get", "list", "watch", "create", "delete", "patch"]
  # Needed for tasks/north_south.md
  - apiGroups: ["gateway.networking.k8s.io"]
    resources: ["gateways", "httproutes"]
    verbs: ["get", "list", "watch", "create", "delete", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: student, namespace: ${NS} }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: Role, name: student }
subjects:
  - { kind: ServiceAccount, name: student, namespace: ${NS} }
YAML

  TOKEN=$(kubectl -n "$NS" create token student --duration=6h)

  cat > "out/${NS}.kubeconfig" << KUBECONFIG
apiVersion: v1
kind: Config
clusters:
  - name: lab
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA}
contexts:
  - name: ${NS}
    context:
      cluster: lab
      user: ${NS}
      namespace: ${NS}
current-context: ${NS}
users:
  - name: ${NS}
    user:
      token: ${TOKEN}
KUBECONFIG

  echo "    flag: ${FLAG}"
done

echo
echo "Wrote $(ls out/*.kubeconfig | wc -l) kubeconfigs to ./out/"
echo "Keep the flags printed above - that's your scorecard for the lab."
echo "Hand out one file per participant. They run:"
echo "  export KUBECONFIG=\$PWD/out/sNN.kubeconfig"
