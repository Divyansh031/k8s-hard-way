# kube-controller-manager

## What is it?

The controller-manager is the **brain that keeps the cluster in the desired state**. It runs a collection of control loops, each watching a specific type of resource and taking action when the real world doesn't match what's declared.

Think of it as a thermostat — it constantly checks the temperature (actual state), compares it to what you set (desired state), and acts to close the gap.

---

## What controllers does it run?

Each controller is a separate loop running inside the same binary:

| Controller | What it watches | What it does |
|---|---|---|
| Node controller | Node heartbeats | Marks nodes NotReady, evicts pods if node goes down |
| Deployment controller | Deployments | Creates/deletes ReplicaSets to match desired replicas |
| ReplicaSet controller | ReplicaSets | Creates/deletes Pods to match desired count |
| Endpoints controller | Services + Pods | Keeps Endpoints objects in sync with healthy pods |
| ServiceAccount controller | Namespaces | Creates default ServiceAccount in every new namespace |
| Namespace controller | Namespaces | Cleans up all resources when a namespace is deleted |
| Job controller | Jobs | Creates pods for jobs, tracks completions |

And many more — the controller-manager runs ~30+ controllers in a single process.

---

## How we set it up

### 1. Kubeconfig copied to `/etc/kubernetes/config/controller-manager.kubeconfig`

The controller-manager uses this to authenticate to the API server as `system:kube-controller-manager`.

### 2. Certs available at `/etc/kubernetes/pki/`

```
/etc/kubernetes/pki/
├── ca.pem                  # Signs new kubelet certs (TLS bootstrapping)
├── ca-key.pem              # Used to sign certificates for new nodes
└── service-account-key.pem # Signs service account JWT tokens for pods
```

### 3. Systemd unit at `/etc/systemd/system/kube-controller-manager.service`

Key flags explained:

| Flag | What it does |
|---|---|
| `--kubeconfig` | How it authenticates to the API server |
| `--cluster-cidr` | Pod IP range — used to set up pod routes |
| `--service-cluster-ip-range` | Must match the API server's range |
| `--cluster-signing-cert-file` | CA cert used to sign new node/kubelet certs |
| `--cluster-signing-key-file` | CA key used to sign new node/kubelet certs |
| `--root-ca-file` | CA cert injected into every pod's `/var/run/secrets` |
| `--service-account-private-key-file` | Signs JWT tokens for pod service accounts |
| `--use-service-account-credentials` | Each controller uses its own service account (more secure) |
| `--leader-elect` | Only one instance is active at a time (for HA setups) |

---

## Communication flow

```
kube-controller-manager
        │
        │ HTTPS :6443 (uses controller-manager.kubeconfig)
        ▼
  kube-apiserver
        │
        ├── watches for: Deployments, ReplicaSets, Nodes, Jobs, etc.
        │
        └── writes back: creates Pods, updates status, creates Endpoints
```

The controller-manager **never talks to etcd directly**. All reads and writes go through the API server. It uses the **watch** mechanism — the API server pushes change notifications to it, rather than the controller-manager polling.

---

## The reconciliation loop (how every controller works)

```
loop forever:
  desired = what the user declared (e.g. 3 replicas)
  actual  = what's currently running (e.g. 2 pods exist)

  if actual != desired:
    take action (e.g. create 1 more pod)
```

This is why Kubernetes is self-healing — if you manually delete a pod, the ReplicaSet controller notices the count dropped and creates a replacement within seconds.

---

## Why it needs the CA key

In production clusters, new nodes bootstrap by requesting a certificate. The controller-manager (specifically the CSR approver) signs those certificates using `ca-key.pem`. In our setup we're manually distributing certs, so this is less critical right now — but it's required by the binary regardless.

---

## Verify it's working

```bash
# Check service status
sudo systemctl status kube-controller-manager

# Check logs
sudo journalctl -u kube-controller-manager -n 50 --no-pager

# Verify via API server
kubectl get componentstatuses \
  --kubeconfig=/vagrant/kubeconfigs/generated/admin.kubeconfig
# Should show: controller-manager   Healthy   ok
```

---

## Script

`scripts/controller-manager.sh` — downloads the binary, writes the systemd unit, and starts the service.

Env vars required:
- `KUBERNETES_VERSION` — which binary to download
- `POD_CIDR` — pod IP range passed to `--cluster-cidr`
- `SERVICE_CIDR` — must match the API server's `--service-cluster-ip-range`