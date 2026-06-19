# kube-scheduler

## What is it?

The scheduler is responsible for one thing: **deciding which node a pod should run on**. It doesn't start the pod — that's kubelet's job. It just picks the node and writes that decision to the API server.

Think of it as an air traffic controller — it doesn't fly the planes, it just assigns them to runways based on available capacity and constraints.

---

## What does it do?

1. Watches the API server for pods that have no node assigned (`spec.nodeName` is empty)
2. For each unscheduled pod, runs through a set of filters and scoring rules
3. Picks the best node
4. Writes the node name back to the pod's `spec.nodeName` via the API server
5. The kubelet on that node sees the pod is assigned to it and starts it

---

## Scheduling process in detail

### Phase 1 — Filtering (which nodes can run this pod?)

The scheduler eliminates nodes that can't satisfy the pod's requirements:

- Does the node have enough CPU and memory?
- Does the node satisfy `nodeSelector` or `nodeAffinity` rules?
- Does the node have the required taints tolerated by the pod?
- Are the required ports available?
- Are the required volumes accessible from this node?

### Phase 2 — Scoring (which remaining node is best?)

The scheduler scores each eligible node:

- Prefer nodes with the most available resources (spread load)
- Prefer nodes that already have the required image cached
- Prefer nodes in different zones (for HA)
- Custom scoring via priority functions

The node with the highest score wins.

---

## How we set it up

### 1. Config file at `/etc/kubernetes/config/kube-scheduler.yaml`

```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: /etc/kubernetes/config/scheduler.kubeconfig
leaderElection:
  leaderElect: true
```

The config file tells the scheduler which kubeconfig to use to talk to the API server, and enables leader election for HA setups.

### 2. Kubeconfig at `/etc/kubernetes/config/scheduler.kubeconfig`

The scheduler authenticates to the API server as `system:kube-scheduler`. This identity has just enough RBAC permissions to watch pods and write node assignments — nothing more.

### 3. Systemd unit at `/etc/systemd/system/kube-scheduler.service`

```
ExecStart=/usr/local/bin/kube-scheduler \
  --config=/etc/kubernetes/config/kube-scheduler.yaml \
  --v=2
```

The binary just needs the config file path. Everything else is in `kube-scheduler.yaml`.

---

## Communication flow

```
kube-scheduler
      │
      │ HTTPS :6443 (uses scheduler.kubeconfig)
      ▼
kube-apiserver
      │
      ├── watches: pods where spec.nodeName == ""
      │
      └── writes: pod.spec.nodeName = "worker-1"  ← the scheduling decision
                        │
                        ▼
                  kubelet on worker-1 sees the pod assigned to it and starts it
```

The scheduler never talks to kubelets. It only talks to the API server. The kubelet on each node watches the API server for pods assigned to its node.

---

## Leader election

`--leader-elect=true` means if you run multiple schedulers (for HA), only one is active at a time. They compete for a lock stored in the API server. You can see the current leader:

```bash
kubectl get lease kube-scheduler -n kube-system \
  --kubeconfig=/vagrant/kubeconfigs/generated/admin.kubeconfig -o yaml
```

In our single-controller setup this doesn't matter much, but it's required by the config so we enable it.

---

## Verify it's working

```bash
# Check service status
sudo systemctl status kube-scheduler

# Check logs — look for "Successfully acquired lease"
sudo journalctl -u kube-scheduler -n 50 --no-pager

# Verify via API server
kubectl get componentstatuses \
  --kubeconfig=/vagrant/kubeconfigs/generated/admin.kubeconfig
# Should show: scheduler   Healthy   ok
```

When you later deploy a pod and it gets a node assigned, that's the scheduler working.

---

## Script

`scripts/scheduler.sh` — downloads the binary, writes the config file and systemd unit, and starts the service.

Env vars required:
- `KUBERNETES_VERSION` — which binary to download