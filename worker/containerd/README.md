# 📦 Kubernetes The Hard Way — containerd Runtime

## 1. What is containerd?

**containerd** is a high-level **container runtime**. It is responsible for:

- Pulling container images from registries (Docker Hub, etc.)
- Managing the lifecycle of containers (create, start, stop, pause, remove)
- Managing container storage (layers, snapshots)
- Executing containers using a lower-level runtime
- Providing a gRPC API (CRI — Container Runtime Interface) that kubelet can talk to

In modern Kubernetes (v1.24+), Docker is no longer the default. Kubernetes uses the **CRI standard**, and **containerd** is the most popular CRI-compatible runtime.

### Mental Model

```text
kubectl / API Server
        ↓
     kubelet
        ↓ (CRI)
     containerd
        ↓ (OCI)
     runc + kernel
```

---

## 2. containerd in this Repo (`scripts/containerd.sh`)

This script runs **only on worker nodes**.

### Step-by-step breakdown of the script

### A. Dependencies installed

```bash
apt-get install -y apt-transport-https ca-certificates socat conntrack ipset
```

### Why each one?

- **`apt-transport-https` + `ca-certificates`**: Required to securely download packages over HTTPS (used when adding repositories, though not heavily used here).
- **`socat`**: Very important. It allows bidirectional data transfer between two endpoints. Used by:
  - `kubectl port-forward`
  - Some debugging tools
  - Many Kubernetes components expect it to be present.
- **`conntrack`**: Linux connection tracking tool. **Critical for networking**.
  - Kubernetes Services (especially with `iptables` mode used by kube-proxy) rely on connection tracking to maintain stateful connections.
  - Without it, Services (ClusterIP, NodePort) often break.
- **`ipset`**: Used by kube-proxy (iptables mode) to efficiently manage large sets of IP addresses/ports for load balancing.

These are classic **Kubernetes node prerequisites**.

### B. Kernel Modules & Sysctl Settings

```bash
modprobe overlay
modprobe br_netfilter

# sysctl settings
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
```

### Why?

- `overlay`: Filesystem driver used by containerd for image layers (efficient storage).
- `br_netfilter`: Enables iptables rules to work on bridged traffic — **essential for pod-to-pod and pod-to-Service communication**.
- `ip_forward`: Allows the node to route packets between pods and the outside world.
- Bridge netfilter calls: Lets iptables see traffic going through the CNI bridge.

These are the **Linux networking foundations** required for any container networking.

---

## 3. Why do we need runc?

**runc** is the low-level **OCI (Open Container Initiative) runtime**.

- containerd is a **high-level** daemon (image management, API, supervision).
- runc is the **low-level** tool that actually uses Linux kernel features (`cgroups`, `namespaces`, `seccomp`, `capabilities`, etc.) to create and run a container.

### Relationship

```text
containerd → calls → runc → creates container using kernel primitives
```

In the script:

```bash
wget https://github.com/opencontainers/runc/releases/download/v1.2.3/runc.amd64
mv runc.amd64 /usr/local/sbin/runc
```

### Why install it separately?

Newer versions of containerd do not always bundle runc. Installing it explicitly ensures compatibility and control over the version.

---

## 4. Cgroup Driver — Why `SystemdCgroup = true` is Critical

This is one of the most important configurations in the entire setup.

### What are cgroups?

cgroups (control groups) are a Linux kernel feature that allows the OS to:

- Limit CPU, memory, I/O for processes
- Account for resource usage
- Kill processes when limits are exceeded

### Two main cgroup drivers in Kubernetes

| Driver | Managed By | Pros | Cons | Recommendation |
|----------|------------|------|------|---------------|
| `cgroupfs` | Kubernetes | Simple | Can conflict with systemd | Not recommended |
| `systemd` | systemd | Better integration, stability | Slightly more complex | **Recommended** |

### In this repo

```bash
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

### Why we must use systemd cgroup driver

1. **Consistency**: The host OS (Ubuntu) uses systemd. Using the same driver avoids split-brain resource accounting.
2. **Kubelet compatibility**: Kubelet also uses `cgroupDriver: systemd` in its config (`kubelet-config.yaml`).
3. **Stability**: Prevents issues with memory limits, OOM kills, and resource reporting.
4. **Production standard**: Almost all real-world Kubernetes clusters (including GKE, EKS, AKS) use `systemd`.

If the cgroup drivers mismatch between kubelet and containerd, you will see weird errors like:

- Pods stuck in `Pending`
- Incorrect resource metrics
- OOM kills not working properly

---

## 5. Full Picture — How containerd fits in the boot sequence

On a worker node:

1. `common.sh` → basic setup + IP forwarding
2. `containerd.sh` → container runtime + runc + systemd cgroup
3. `cni.sh` → networking plugins
4. `kubelet.sh` → starts kubelet, which connects to containerd socket

Once everything is up:

- Kubelet watches API server for pods assigned to this node.
- When a pod is scheduled:
  - Kubelet asks containerd (via CRI) to create the pod's containers.
  - containerd uses runc to actually spawn them.
  - CNI assigns IP and network namespace.

---

## Summary – Why this specific setup?

- **containerd**: Modern, lightweight, Kubernetes-native runtime.
- **Dependencies** (`socat`, `conntrack`, `ipset`): Make networking and debugging work reliably.
- **Kernel modules + sysctl**: Enable proper container networking.
- **runc**: The actual container executor.
- **Systemd cgroup driver**: Ensures stability and consistency with the host OS and kubelet.