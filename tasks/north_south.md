# North-South Traffic

**Time: 30 minutes.**


## The scenario

Last session was east-west: traffic between pods inside the cluster, and you
hardened it with NetworkPolicy. Today is north-south: traffic in from the
internet, and out to it. Different problem, different layer, and the two
don't substitute for each other, that's the point you'll end on.


## Setup

1. Export your kubeconfig if it isn't already:
   `export KUBECONFIG=$PWD/sNN.kubeconfig`
   - Same file, same namespace, as `tasks/pod_security.md`.
2. Deploy the app this lab exposes:
   `kubectl apply -f manifests/north-south/shop-pod.yaml`
   - Same image as every other lab. `kubectl get pod shop -w` until `Running`.


## Step 1: The pod IP problem

1. Get the pod's own IP:
   `kubectl get pod shop -o wide`
   - Note the `IP` column, something like `10.244.x.x`.
2. Try reaching it directly, from your own terminal (not `kubectl exec`, an actual `curl` from where you're sitting):
   `curl --max-time 5 http://<that-ip>:8080`
   - Expect it to hang and time out. No route to that address exists outside the cluster.
3. Compare it to a node's address:
   `kubectl get nodes -o wide`
   - Node `INTERNAL-IP` looks like `10.224.x.x`, a different range entirely. That's a real subnet in your Azure VNet. `10.244.x.x` is an overlay network that exists only inside the cluster (Azure CNI Overlay hands out those addresses), and nothing in the VNet knows how to route to it. This is true from anywhere outside the cluster, not just from here.

Everything in the rest of this lab is a layer added on top to solve exactly
this one problem. A pod IP is not "just an IP" that works like any other,
the two address ranges above are the reason why.


## Step 2: The Service ladder

Three Service types, each one containing the one before it. Same object,
re-applied with a different `type` each time, watch what changes.

1. `kubectl apply -f manifests/north-south/shop-svc-clusterip.yaml`
   - `type: ClusterIP` gets a virtual IP from the cluster's service range. Not a machine, no network card owns that address, it's a forwarding rule kube-proxy writes on every node: traffic to this IP gets rewritten to a real pod. Solves pod churn, not exposure. Still nothing you can reach from outside.
2. `kubectl apply -f manifests/north-south/shop-svc-nodeport.yaml`
   - `type: NodePort` is ClusterIP plus a port between 30000-32767 opened on every node. Hit any node on that port and you land on the Service, even if the pod isn't on the node you hit. Still won't work from your own terminal though: node IPs are the same private `10.224.x.x` range from step 1.
3. `kubectl get svc shop`
   - Note the `PORT(S)` column, something like `80:31842/TCP`. That's the NodePort, already allocated, already working. It doesn't go away in the next step, it gets hidden underneath.
4. `kubectl apply -f manifests/north-south/shop-svc-loadbalancer.yaml`
   - `type: LoadBalancer` is NodePort plus "cloud, give me a real IP and point it at these nodes." This is the one that costs real money and takes a minute or two, Azure has to actually provision something.
5. `kubectl get svc shop -w` (Ctrl-C once `EXTERNAL-IP` is a real address, not `<pending>`)
6. `curl http://<EXTERNAL-IP>`
   - Works, from your own terminal, no `kubectl exec` involved. This is the first thing in the whole lab reachable from outside the cluster.


## Step 3: What Azure actually did

Nowhere in `shop-svc-loadbalancer.yaml` does the word "Azure" appear. So
where did that external IP come from?

1. `kubectl get svc shop -o wide`
   - Compare `PORT(S)` here to what you saw in step 2, the same NodePort is still listed, e.g. `80:31842/TCP`. The load balancer's rule points straight at it. Nothing in step 2 became obsolete, it's still doing the work.
2. `kubectl describe svc shop`
   - Look for `LoadBalancer Ingress`, the external IP, and the same NodePort again under `NodePort:`.

What actually happened between `<pending>` and a real IP: AKS runs a
component called the cloud controller manager. A controller inside it
watches for Services of type `LoadBalancer`. When one appears, it calls the
Azure ARM API (the same API the Azure portal uses) and creates a public IP, a
frontend IP config, a backend pool containing your nodes, a health probe, and
a load balancing rule, then writes the address back into the Service. That
wait was an API call, not Kubernetes thinking.

Two things worth knowing, if you have Azure CLI access to look (most
participants won't, and that's fine, this part is instructor-shown):

- None of this lives in your cluster's own resource group. AKS creates a
  second one, `MC_<rg>_<cluster>_<region>`, holding the load balancer, public
  IPs, node VMs and disks.
- There's one load balancer for the whole cluster, named `kubernetes`. Every
  participant's `LoadBalancer` Service adds another frontend IP and rule to
  that same one, it doesn't create a new load balancer each time.


## Step 4: Gateway API, a smarter router in front of the same door

One IP per app doesn't scale past a handful of apps, and a `LoadBalancer`
Service only reads IP addresses and ports, it has never heard of HTTP. Two
apps on the same IP and port (`shop.example.com`, `admin.example.com`) look
identical to it. Gateway API reads the actual HTTP request, so it can route
on hostname or path.

1. `kubectl apply -f manifests/north-south/shop-gateway.yaml`
   - Creates two objects: a `Gateway` (the listener) and an `HTTPRoute` (routes traffic matching `shop.example.com` to the `shop` Service).
2. `kubectl get svc`
   - You'll see a **third** Service you never wrote, something like `shop-gateway-istio`, also `type: LoadBalancer`. The gateway is just pods, and pods need exposing like anything else, so the controller made one automatically. You authored two objects; this appeared on its own.
3. Wait for it to get an address:
   `kubectl wait --for=condition=programmed gateways.gateway.networking.k8s.io shop-gateway`
   `export INGRESS_IP=$(kubectl get gateways.gateway.networking.k8s.io shop-gateway -o jsonpath='{.status.addresses[0].value}')`
4. Call it with the hostname the route matches on:
   `curl -H "Host: shop.example.com" http://$INGRESS_IP/`
   - Works. You're not editing DNS, the `Host` header is doing what a real DNS-resolved request would do.
5. Try it without the header:
   `curl http://$INGRESS_IP/`
   - No route matches, since the `HTTPRoute` only matches `shop.example.com`. This is exactly what lets one IP serve many apps: the gateway reads the request before deciding where it goes.

Everything from step 3 is still underneath this: a real Azure load balancer,
a public IP, a backend pool, a NodePort. Gateway API didn't replace any of
it, it's a smarter router sitting behind the same front door you already
built.


## Step 5: The full picture

One request, traced end to end:

Browser resolves `shop.example.com` to a public IP → Azure load balancer
forwards to some node's IP, on the NodePort → kube-proxy forwards to a
gateway pod → the gateway pod is the first thing in this entire chain that
reads the HTTP request, sees the hostname, and picks a backend → forwarded to
the `shop` pod on port 8080.

The sentence worth remembering: **nothing outside the cluster ever addresses
a pod IP directly.** Every hop inward lands on a node IP first, exactly like
step 1 said, five layers later.

Three separate enforcement points sit along that path, and they don't
overlap:

| Layer | Sees | Enforced by |
|---|---|---|
| Node subnet | Node IPs, source ranges | An NSG (not covered hands-on here) |
| The gateway | Hostname, path, headers | The `HTTPRoute` you just wrote |
| Pod-to-pod traffic | Pod labels, inside the overlay only | `NetworkPolicy` (Calico), from `tasks/east_west.md` |

The sentence that ties last session to this one: **`NetworkPolicy` decides
which pods may talk to your app. It does not decide whether your app has a
public IP.** Adding a `NetworkPolicy` won't un-expose a `LoadBalancer`
Service, and deleting every `LoadBalancer` Service won't make `NetworkPolicy`
unnecessary. They're answering two different questions.


## Step 6 (optional): Traffic going out

*Read and discuss, nothing to run. Skip if you're behind.*

By default, AKS sends all outbound traffic through the same load balancer
you've been using inbound. A pod calling an external API gets its source
address rewritten (SNAT'd) to that load balancer's public IP, the whole
cluster leaves as one address. Practical consequence: if a partner needs to
allowlist your traffic, that one IP is what they allowlist, every pod in
every namespace shares it.

Two ways to hardclass this, in order of how often they're actually used:

- **NAT Gateway**: swap the default outbound path for a dedicated NAT
  Gateway resource. Still one shared address (or a small pool), but
  decoupled from the load balancer, and it scales outbound connections
  better under load.
- **Azure Firewall with a forced route (UDR)**: send `0.0.0.0/0` from the
  node subnet through a firewall, and filter exactly what the cluster is
  allowed to reach. The most control, and the most to configure correctly,
  since it means every node's default route now goes through a firewall
  rule set you maintain.

One line that closes the loop with step 5: because outbound traffic is
SNAT'd to one shared address, an NSG or firewall downstream only ever sees
node IPs, never pod IPs. You cannot write a firewall rule for "only pod X's
egress", that granularity does not exist at that layer. `NetworkPolicy`
egress rules, enforced by Calico inside the cluster, are the only place that
per-pod distinction still exists.


## Cleanup

`LoadBalancer` Services and the one Gateway API creates are real, billable
Azure resources. Delete them when you're done rather than leaving them
running:

```bash
kubectl delete -f manifests/north-south/shop-gateway.yaml
kubectl delete svc shop
kubectl delete pod shop
```

Or run `./scripts/cleanup-participants.sh` between sessions, it deletes the
whole namespace, load balancers and public IPs included.
