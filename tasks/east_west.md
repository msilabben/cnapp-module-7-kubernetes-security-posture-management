# East-West Traffic and NetworkPolicy

**Time: 30-35 minutes.**


## The scenario

Traffic that crosses the cluster boundary (a browser reaching your app) is
called north-south. Traffic between workloads inside the cluster (your app
calling a database) is called east-west. One customer click is a single
north-south request, but it can trigger many internal east-west calls. Most
traffic inside a real cluster is east-west.

Azure's own network controls, NSGs and Azure Firewall, work on subnets and
virtual machine network cards. Pods are not virtual machines. Two pods on the
same node never leave the machine at all; two pods on different nodes travel
wrapped inside the cluster's own network. Either way, Azure never sees
"frontend talked to database", only "node talked to node", if it sees
anything at all.

**Goal:** prove that today, any pod in any namespace can reach any other
pod's Service, then lock that down with NetworkPolicy without breaking your
own app.


## Setup

1. If you haven't already, export the kubeconfig your instructor gave you:
   `export KUBECONFIG=$PWD/out/sNN.kubeconfig`
   - Same file, same namespace, as `tasks/pod_security.md`.
2. Deploy your frontend:
   `kubectl apply -f manifests/east-west/frontend-pod.yaml`
   - Your foothold for this lab, a plain pod with `curl` installed.
3. Deploy your database:
   `kubectl apply -f manifests/east-west/database.yaml`
   - Creates both a Pod and a Service in one file (the two YAML documents are separated by `---`). The pod serves your namespace's flag over HTTP, the Service is what makes it reachable by a fixed name.
4. Wait for both to start:
   `kubectl get pods -w` (Ctrl-C once both say `Running`)

**Wait for everyone in the room to finish Setup before continuing.** Step 3
only works once your neighbours' databases exist too.


## Step 1: Where does traffic actually go?

1. Get a shell in your frontend:
   `kubectl exec -it frontend -- bash`
2. Call your own database by name:
   `curl http://database`
   - Returns your flag. `database` resolves through Kubernetes' internal DNS to a stable virtual IP (the Service), which is then rewritten by the node to the address of a real pod. You never touched a pod IP directly.
3. Leave the pod and look at what's actually running (from your own terminal, not inside the pod):
   `kubectl get pods -o wide`
   - Notice `frontend` and `database` have different IP addresses. Two separate processes, two separate pod IPs.
4. Look at the Service:
   `kubectl get svc database`
   - Shows a `ClusterIP`, a stable address that is not either pod's own IP.
5. Look at what the Service actually points at:
   `kubectl get endpoints database`
   - Lists the real pod IP currently backing the Service. This is the translation table kube-proxy uses to rewrite traffic. An empty list here always means "the Service's label selector matched nothing."


## Step 2: Pods move, the Service doesn't

1. Note the database pod's current IP:
   `kubectl get pod database -o jsonpath='{.status.podIP}{"\n"}'`
2. Delete and recreate it, simulating a restart:
   `kubectl delete pod database`
   `kubectl apply -f manifests/east-west/database.yaml`
   `kubectl get pod database -w` (Ctrl-C once `Running`)
3. Check the IP again:
   `kubectl get pod database -o jsonpath='{.status.podIP}{"\n"}'`
   - Different from step 1. Every pod replacement gets a new address.
4. From your frontend shell, call it the same way as before:
   `curl http://database`
   - Still works, unchanged. The Service's ClusterIP and DNS name never moved, only the pod IP underneath it did. This is exactly why Services exist: `frontend` never needs to know or care what `database`'s current pod IP is.


## Step 3: The flat network problem

Nothing has stopped you from reaching anyone else's Service yet. Prove it.

1. From your frontend shell, call a neighbour's database instead of your
   own. Ask another participant for their namespace, or just try one:
   `curl http://database.s03.svc.cluster.local`
   - Replace `s03` with a real namespace. This is a Service's full DNS name: `<service>.<namespace>.svc.cluster.local`. Their flag comes back, from a namespace you have never been granted any access to.
2. Confirm you really have no `kubectl` access there (from your own terminal, not the pod):
   `kubectl -n s03 get pods`
   - `Forbidden`. Read that against what you just did in step 1: a Kubernetes namespace controls what `kubectl` lets you do. It does nothing to what a pod's own network traffic can reach. Those are two completely separate walls, and only one of them exists right now.

**Nothing was exploited here.** No CVE, no misconfigured pod. This is what a
Kubernetes cluster does by default: a flat network where every pod can dial
every other pod's Service, in any namespace.


## Step 4: NetworkPolicy, allow only what's needed

1. Block all incoming traffic to every pod in your own namespace:
   `kubectl apply -f manifests/east-west/netpol-default-deny-ingress.yaml`
   - An empty `podSelector: {}` matches every pod in the namespace. With no `ingress` rules listed, nothing is allowed in, not even from your own frontend.
2. From your frontend shell, try your own database again:
   `curl http://database`
   - Now hangs or times out. The moment one policy selects a pod, everything not explicitly allowed to reach it is denied. There is no message anywhere saying this pod is now locked down, you have to know it happened because you just did it.
3. Re-open exactly the path you actually need:
   `kubectl apply -f manifests/east-west/netpol-allow-frontend-to-database.yaml`
   - Allows ingress to pods labelled `app: database`, only from pods labelled `app: frontend`, only on port 8080, and only within this same namespace (a bare `podSelector` with no `namespaceSelector` never matches pods in a different namespace, even if they carry the same label).
4. Try your own database again:
   `curl http://database`
   - Works again.
5. Ask the neighbour whose database you reached in step 3 to try reaching yours the same way, or ask them for their namespace and try it in reverse. Either direction should now fail.

Two NetworkPolicy objects, no application change, and the exact attack from
step 3 no longer works.


## Step 5 (optional): NetworkPolicy can break DNS

Skip this step if you're short on time, it's a bonus lesson, not a
requirement for the lab.

1. Block all outbound traffic from your frontend:
   `kubectl apply -f manifests/east-west/netpol-deny-all-egress-frontend.yaml`
2. From your frontend shell:
   `curl http://database`
   - Fails, but read the error carefully, it's a name resolution failure, not a connection failure. CoreDNS, the service that answers `database`'s name lookup, itself runs as ordinary pods in `kube-system`. Blocking all egress blocked the DNS query before it could even ask "what is database's address."
3. Allow DNS specifically, on top of the policy from step 1:
   `kubectl apply -f manifests/east-west/netpol-allow-dns-egress.yaml`
   - NetworkPolicy objects for the same pod are additive: this does not replace the deny-all policy, it stacks with it.
4. Try again:
   `curl http://database`
   - Name resolution now succeeds (you can confirm with `getent hosts database`), but the actual connection still fails. Only DNS traffic was allowed; nothing permits reaching `database` on port 8080 itself. Resolving a name and reaching what it points to are two different permissions.
5. Clean up so your app keeps working for the rest of the session:
   `kubectl delete -f manifests/east-west/netpol-deny-all-egress-frontend.yaml`
   `kubectl delete -f manifests/east-west/netpol-allow-dns-egress.yaml`


## Debrief

| Check | Before NetworkPolicy | After step 4 |
|---|---|---|
| Own frontend to own database | works | works |
| Neighbour's frontend to your database | works | blocked |
| `kubectl -n <neighbour>` | Forbidden | Forbidden (unchanged) |

Three things worth remembering:

1. **Namespaces separate permissions, not traffic.** `kubectl` access and
   network reachability are enforced by entirely different mechanisms.
2. **NetworkPolicy is allow-only.** There is no deny rule and no priority
   order. You list what's permitted; everything else selected by a policy is
   blocked.
3. **A cluster with no NetworkPolicy engine enforces nothing,** silently. A
   policy that matches zero traffic looks identical to a policy that isn't
   enforced at all. If NetworkPolicy ever appears not to work, confirm the
   engine is actually running before assuming your YAML is wrong.
