# 🚀 kubelet — The Kubernetes Node Agent

## Overview

**kubelet** is the **primary Kubernetes agent** that runs on **every node** in the cluster. It is the component that makes each machine (physical or virtual) behave as a Kubernetes Node.

You can think of kubelet as the **"local manager"** on each worker — it is responsible for everything that happens on that specific machine.

---

# Role in This Repository

* Installed **primarily on worker nodes** via `scripts/kubelet.sh`
* Uses Kubernetes version from `settings.yaml`: `v1.36.0`
* Works closely with:

  * **containerd** (container runtime)
  * **CNI** (networking)
  * **kube-proxy** (services)
  * **API Server** (cluster state)

In this single-controller setup, kubelet mainly runs on the worker.

In HA production clusters, kubelet also runs on control-plane nodes.

---

# What is kubelet?

The kubelet is a **long-running process** that:

* Registers the node with the Kubernetes API Server
* Continuously watches the API Server for Pods assigned to this node
* Instructs the container runtime (containerd) to start and stop pods
* Monitors pod health (liveness, readiness, startup probes)
* Reports node status, capacity, and conditions back to the API Server
* Handles volume mounting, Secrets, ConfigMaps, and container logs
* Performs garbage collection for images and containers

---

## Mental Model

```text
API Server (Cluster State)
          │
          │ Watch
          ▼
       kubelet
   (on every node)
          │
          ▼
   containerd + CNI
          │
          ▼
      Actual Pods
```

kubelet is the bridge between the desired state stored in Kubernetes and the actual state running on the machine.

---

# Script: `scripts/kubelet.sh`

## Key Steps Performed

### 1. Download kubelet Binary

```bash
wget https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64/kubelet
```

Downloads the kubelet binary corresponding to the Kubernetes version defined in `settings.yaml`.

---

### 2. Copy TLS Artifacts

The script copies:

```text
worker-1.pem
worker-1-key.pem
ca.pem
worker-1.kubeconfig
```

into:

```text
/var/lib/kubelet/
/var/lib/kubernetes/
```

Example:

```text
worker-1.pem                → /var/lib/kubelet/
worker-1-key.pem            → /var/lib/kubelet/
worker-1.kubeconfig         → /var/lib/kubelet/kubeconfig
ca.pem                      → /var/lib/kubernetes/
```

These files allow kubelet to securely authenticate with the API Server.

---

### 3. Create Kubelet Configuration

Location:

```bash
/var/lib/kubelet/kubelet-config.yaml
```

Example:

```yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1

authentication:
  webhook:
    enabled: true
  anonymous:
    enabled: false

authorization:
  mode: Webhook

clusterDomain: cluster.local

clusterDNS:
  - 10.32.0.10

podCIDR: 10.200.1.0/24

resolvConf: /run/systemd/resolve/resolv.conf

runtimeRequestTimeout: "15m"

tlsCertFile: /var/lib/kubelet/worker-1.pem
tlsPrivateKeyFile: /var/lib/kubelet/worker-1-key.pem

cgroupDriver: systemd
```

---

# Important Configuration Settings

## Authentication

```yaml
authentication:
  webhook:
    enabled: true
  anonymous:
    enabled: false
```

### What it does

* Disables anonymous requests
* Requires authentication
* Delegates authentication checks to the API Server

This ensures only trusted clients can communicate with kubelet.

---

## Authorization

```yaml
authorization:
  mode: Webhook
```

### What it does

After authentication succeeds, kubelet asks the API Server:

```text
"Is this user allowed to perform this action?"
```

The API Server evaluates RBAC policies and returns:

```text
ALLOW
or
DENY
```

This prevents unauthorized access to kubelet APIs.

---

## clusterDomain

```yaml
clusterDomain: cluster.local
```

Defines the internal DNS suffix used by Kubernetes.

Example:

```text
nginx.default.svc.cluster.local
```

---

## clusterDNS

```yaml
clusterDNS:
  - 10.32.0.10
```

CoreDNS Service IP.

Pods receive this address in:

```bash
/etc/resolv.conf
```

allowing them to resolve:

```text
service-name.namespace.svc.cluster.local
```

---

## podCIDR

```yaml
podCIDR: 10.200.1.0/24
```

Defines the pod subnet assigned to this node.

Example:

```text
worker-1 → 10.200.1.0/24
worker-2 → 10.200.2.0/24
```

The CNI plugin allocates pod IPs from this range.

---

## resolvConf

```yaml
resolvConf: /run/systemd/resolve/resolv.conf
```

Specifies which DNS configuration file kubelet should pass to pods.

Using the systemd-resolved file avoids common DNS issues on Ubuntu systems.

---

## runtimeRequestTimeout

```yaml
runtimeRequestTimeout: "15m"
```

Maximum amount of time kubelet waits for the container runtime.

Example operations:

* Pulling large images
* Starting containers
* Stopping containers

---

## TLS Certificates

```yaml
tlsCertFile: /var/lib/kubelet/worker-1.pem

tlsPrivateKeyFile: /var/lib/kubelet/worker-1-key.pem
```

These files enable kubelet's HTTPS server.

Used for secure communication with:

* API Server
* kubectl (through API Server)
* Monitoring tools

---

## cgroupDriver

```yaml
cgroupDriver: systemd
```

Must match containerd configuration.

Earlier, containerd was configured with:

```toml
SystemdCgroup = true
```

Using different cgroup drivers can cause:

* Pod startup failures
* Incorrect resource accounting
* Memory limit issues
* OOM handling problems

---

# Create systemd Service

The script creates a systemd unit for kubelet.

Key flags:

```bash
--config=/var/lib/kubelet/kubelet-config.yaml
--container-runtime-endpoint=unix:///var/run/containerd/containerd.sock
--kubeconfig=/var/lib/kubelet/kubeconfig
--register-node=true
--v=2
```

---

## Explanation of Important Flags

### Configuration File

```bash
--config=/var/lib/kubelet/kubelet-config.yaml
```

Loads the kubelet configuration file.

---

### Container Runtime Endpoint

```bash
--container-runtime-endpoint=unix:///var/run/containerd/containerd.sock
```

Connects kubelet to containerd via CRI.

Flow:

```text
kubelet
    │
    ▼
containerd.sock
    │
    ▼
containerd
```

---

### Kubeconfig

```bash
--kubeconfig=/var/lib/kubelet/kubeconfig
```

Contains:

* API Server address
* Certificates
* Authentication information

Used by kubelet to communicate securely with the cluster.

---

### Register Node

```bash
--register-node=true
```

Automatically registers the node.

Without this flag:

```bash
kubectl get nodes
```

would not show the worker.

---

### Verbosity

```bash
--v=2
```

Sets kubelet log level.

Useful for debugging while keeping output manageable.

---

# How kubelet Works — Pod Lifecycle

Suppose you run:

```bash
kubectl run nginx --image=nginx
```

---

## Step 1 — API Server Stores Desired State

The Pod object is stored in etcd.

---

## Step 2 — Scheduler Assigns Node

Example:

```text
nginx → worker-1
```

---

## Step 3 — kubelet Detects New Pod

kubelet continuously watches the API Server.

It notices:

```text
A new Pod has been assigned to me.
```

---

## Step 4 — kubelet Calls CNI

The CNI plugin:

* Creates a network namespace
* Creates a veth pair
* Assigns an IP address
* Configures routes

Example:

```text
10.200.1.2/24
```

---

## Step 5 — kubelet Calls containerd

Through CRI:

```text
kubelet
   │
   ▼
containerd
```

containerd:

* Pulls the image
* Creates the container
* Starts the container

---

## Step 6 — kubelet Starts Health Checks

Monitors:

* Liveness probes
* Readiness probes
* Startup probes

---

## Step 7 — kubelet Reports Status

Updates API Server:

```text
Pending
Running
Succeeded
Failed
```

---

## Step 8 — Continuous Monitoring

kubelet never stops monitoring the pod.

If a container crashes:

```text
Container Exit
      ↓
kubelet detects failure
      ↓
container restarted
```

according to the Pod restart policy.

---

# Key Directories Used

| Directory                             | Purpose                             |
| ------------------------------------- | ----------------------------------- |
| `/var/lib/kubelet/`                   | Main kubelet working directory      |
| `/var/lib/kubelet/pods/`              | Pod directories and mounted volumes |
| `/var/lib/containerd/`                | Container runtime data              |
| `/var/run/containerd/containerd.sock` | CRI socket                          |
| `/etc/cni/net.d/`                     | CNI configurations                  |
| `/var/lib/kubernetes/`                | CA certificate storage              |

---

# Verification Commands

## Check Service

```bash
sudo systemctl status kubelet
```

---

## Check Logs

```bash
journalctl -u kubelet -n 100 --no-pager
```

---

## Check Registered Nodes

```bash
kubectl get nodes \
  --kubeconfig=/vagrant/kubeconfigs/generated/admin.kubeconfig
```

---

## Detailed Node Information

```bash
kubectl describe node worker-1
```

---

## Check Kubelet Configuration

```bash
cat /var/lib/kubelet/kubelet-config.yaml
```

---

# Why kubelet is Critical

kubelet is the **only Kubernetes component that directly interacts with both the Linux operating system and the container runtime**.

Without kubelet:

* The node cannot register itself
* Pods cannot start
* Container runtimes are never instructed to create containers
* Health monitoring does not occur
* The node becomes `NotReady`

In practice:

```text
Healthy kubelet
       =
Healthy Kubernetes Node
```

---

# kubelet Communication Flow

```text
                API Server
                     ▲
                     │
             Watch / Report
                     │
                     ▼
                 kubelet
                     │
      ┌──────────────┼──────────────┐
      │              │              │
      ▼              ▼              ▼
  containerd       CNI         Volumes
      │              │
      ▼              ▼
 Containers      Networking
```

---

# Summary — kubelet in This Setup

* Downloads and runs the official kubelet binary
* Uses TLS certificates for secure API Server communication
* Uses webhook authentication and authorization
* Configured to use containerd as its container runtime
* Uses CNI for networking
* Knows its own podCIDR for IP allocation
* Uses the systemd cgroup driver (matches containerd)
* Automatically registers the node (`--register-node=true`)
* Continuously monitors pod health and status

## Final Mental Model

```text
Desired State (etcd)
          │
          ▼
     API Server
          │
          ▼
       kubelet
          │
          ▼
 containerd + CNI
          │
          ▼
   Running Pods
```

**kubelet = "The thing that actually runs your pods on the machine."**

It is the bridge between the declarative world of Kubernetes (desired state stored in etcd) and the real world (running containers on Linux).
