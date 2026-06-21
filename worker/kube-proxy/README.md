# 🔀 kube-proxy — Kubernetes Service Networking

## Overview

**kube-proxy** is the Kubernetes component responsible for **implementing Services**.

While the API Server stores Service definitions and Endpoints, it is **kube-proxy** that makes them actually work at the network level by programming low-level networking rules on each node.

Without kube-proxy, you can create Services (`kubectl get svc` will show them), but you won't be able to reach them reliably from inside or outside the cluster.

---

# Role in This Repository

* Installed on **every worker node** via `scripts/kube-proxy.sh`
* Uses the Kubernetes version defined in `settings.yaml`
* Runs in **iptables mode**
* Uses its own dedicated identity:

  ```text
  system:kube-proxy
  ```
* Authenticates to the API Server using:

  ```text
  kube-proxy.kubeconfig
  ```

---

# What is kube-proxy?

kube-proxy is a long-running process that maintains networking rules on every node.

Its primary job is to make Kubernetes Services work.

It ensures that:

* **ClusterIP Services** are reachable from any pod
* **NodePort Services** are reachable from outside the cluster
* Traffic is load balanced across multiple backend pods
* Session affinity (sticky sessions) works when configured

---

## Supported Service Types in This Setup

### ClusterIP

The default Service type.

```text
Pod
 ↓
ClusterIP
 ↓
Backend Pods
```

The Service receives a virtual IP that is reachable only inside the cluster.

Example:

```text
Service: nginx
ClusterIP: 10.32.0.50
```

Pods connect to:

```text
10.32.0.50
```

without knowing the actual pod IPs behind it.

---

### NodePort

Exposes the Service on a static port on every worker node.

Example:

```text
Node IP: 192.168.56.11
NodePort: 30080
```

Access:

```text
http://192.168.56.11:30080
```

kube-proxy handles forwarding traffic to the correct backend pod.

---

# How kube-proxy Works — Detailed Flow

## Step 1 — Watches the API Server

kube-proxy authenticates using:

```text
kube-proxy.kubeconfig
```

and continuously watches:

* Services
* Endpoints
* EndpointSlices

Whenever something changes:

```text
New Service
New Pod
Pod Deleted
Endpoint Updated
```

kube-proxy updates networking rules automatically.

---

## Step 2 — Translates Objects into Linux Rules

The API Server only stores Kubernetes objects.

Example:

```yaml
kind: Service
metadata:
  name: nginx
spec:
  clusterIP: 10.32.0.50
```

This object alone does nothing.

kube-proxy converts it into:

```text
iptables rules
routing rules
NAT rules
load-balancing rules
```

that Linux can actually use.

---

## Step 3 — Programs iptables

This repository uses:

```yaml
mode: iptables
```

kube-proxy creates NAT and forwarding rules inside:

```text
iptables
```

These rules:

* Intercept traffic going to a Service IP
* Select a backend pod
* Rewrite packet destinations
* Forward packets correctly

---

# Key iptables Chains Created by kube-proxy

## KUBE-SERVICES

Main entry point for Service traffic.

Example:

```text
Client
   ↓
KUBE-SERVICES
   ↓
Service Chain
```

All Service traffic eventually passes through this chain.

---

## KUBE-POSTROUTING

Handles post-routing NAT operations.

Used when packets leave the node.

---

## KUBE-MARK-MASQ

Marks packets that require source NAT (masquerading).

Example:

```text
Pod → Internet
```

Source IP must be rewritten.

---

## KUBE-SVC-XXXXX

Service-specific chain.

Example:

```text
KUBE-SVC-ABCD1234
```

Contains load-balancing logic for one Service.

---

## KUBE-SEP-XXXXX

Endpoint-specific chains.

Example:

```text
KUBE-SEP-POD1
KUBE-SEP-POD2
KUBE-SEP-POD3
```

Each chain represents a backend pod.

---

# Script: `scripts/kube-proxy.sh`

## Key Steps Performed

### 1. Download kube-proxy Binary

```bash
wget https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64/kube-proxy
```

Downloads the kube-proxy binary matching the cluster version.

---

### 2. Copy kubeconfig

```bash
cp /vagrant/kubeconfigs/generated/kube-proxy.kubeconfig \
   /var/lib/kube-proxy/kubeconfig
```

Provides:

* API Server address
* Certificates
* Authentication credentials

Used by kube-proxy to authenticate as:

```text
system:kube-proxy
```

---

### 3. Create Configuration

```yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1

clientConnection:
  kubeconfig: /var/lib/kube-proxy/kubeconfig

mode: iptables

clusterCIDR: 10.200.0.0/16
```

---

# Important Configuration Explained

## clientConnection.kubeconfig

```yaml
clientConnection:
  kubeconfig: /var/lib/kube-proxy/kubeconfig
```

Used to authenticate with the API Server.

Without it:

```text
kube-proxy cannot watch Services or Endpoints
```

---

## mode: iptables

```yaml
mode: iptables
```

Tells kube-proxy to use Linux iptables rules.

Advantages:

* Simple
* Mature
* Works everywhere

Trade-offs:

* Less efficient in very large clusters
* Large rule sets can become slow

---

## clusterCIDR

```yaml
clusterCIDR: 10.200.0.0/16
```

Defines the entire Pod network range.

Example:

```text
worker-1 → 10.200.1.0/24
worker-2 → 10.200.2.0/24
```

Together:

```text
10.200.0.0/16
```

kube-proxy uses this information when deciding:

```text
Should this traffic be masqueraded?
Is this source inside or outside the cluster?
```

---

# systemd Service

The script creates a systemd service.

Main command:

```bash
ExecStart=/usr/local/bin/kube-proxy \
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
```

This starts kube-proxy using the generated configuration file.

---

# Mental Model

```text
Pod A
(on any node)

      │
      ▼

Service ClusterIP
(10.32.0.x)

      │
      ▼

kube-proxy
(iptables rules)

      │
      ▼

Load Balancing

 ┌──────┬──────┬──────┐
 ▼      ▼      ▼
Pod B  Pod C  Pod D
```

The client only knows the Service IP.

kube-proxy decides which backend pod receives the request.

---

# Example — ClusterIP Service Flow

Assume:

```text
Service IP:
10.32.0.50
```

Backend Pods:

```text
10.200.1.2
10.200.1.3
10.200.2.2
```

Traffic flow:

```text
Pod A
   │
   ▼
10.32.0.50
   │
   ▼
iptables rule
   │
   ▼
10.200.1.3
```

On the next request:

```text
Pod A
   │
   ▼
10.32.0.50
   │
   ▼
iptables rule
   │
   ▼
10.200.2.2
```

This provides Service-level load balancing.

---

# Example — NodePort Flow

User accesses:

```text
http://192.168.56.11:30080
```

Traffic flow:

```text
External User
      │
      ▼
NodePort 30080
      │
      ▼
kube-proxy
      │
      ▼
Backend Pod
```

No application needs to listen directly on port 30080.

kube-proxy handles the forwarding.

---

# What kube-proxy Enables

| Feature           | How kube-proxy Helps            |
| ----------------- | ------------------------------- |
| ClusterIP         | iptables DNAT rules             |
| Load Balancing    | Probabilistic backend selection |
| NodePort          | Port forwarding on every node   |
| External Traffic  | Source NAT (masquerading)       |
| Service Discovery | Works with CoreDNS              |

---

# Interaction with Other Components

## kubelet

Creates and manages Pods.

```text
kubelet
   ↓
Pods
```

---

## CNI

Provides pod networking.

```text
CNI
 ↓
Pod IPs
```

---

## containerd

Runs containers.

```text
containerd
 ↓
Containers
```

---

## kube-proxy

Makes Services work.

```text
Service IP
 ↓
Backend Pod
```

---

# Verification Commands

## Check Service Status

```bash
sudo systemctl status kube-proxy
```

---

## Check Logs

```bash
journalctl -u kube-proxy -n 50 --no-pager
```

---

## View iptables Rules

```bash
sudo iptables -t nat -L -n -v
```

Useful filters:

```bash
sudo iptables -t nat -L -n -v | grep KUBE
```

or

```bash
sudo iptables -t nat -L -n -v | grep -E "KUBE-SVC|KUBE-SEP"
```

---

## Check Services

```bash
kubectl get svc
```

---

## Test a Service

```bash
curl <ClusterIP>
```

Example:

```bash
curl 10.32.0.50
```

---

# Common Troubleshooting

## Services Exist But Don't Work

Check:

```bash
sudo systemctl status kube-proxy
```

---

## Missing iptables Rules

Verify:

```bash
sudo iptables -t nat -L -n -v | grep KUBE
```

---

## Service Has No Endpoints

Check:

```bash
kubectl get endpoints
```

A Service without endpoints cannot forward traffic.

---

## Authentication Issues

Check:

```bash
cat /var/lib/kube-proxy/kubeconfig
```

Ensure certificates and API Server address are correct.

---

# Limitations in This Setup

* Uses iptables mode
* Not optimized for extremely large clusters
* No IPVS support
* Depends on the simple bridge-based CNI setup
* Cross-node pod routing still depends on the underlying network configuration

As discussed in the CNI section, kube-proxy does not create inter-node pod routes.

---

# Position in the Kubernetes Stack

```text
containerd
     │
     ▼
Runs Containers

CNI
     │
     ▼
Provides Pod Networking

kubelet
     │
     ▼
Manages Pods

kube-proxy
     │
     ▼
Makes Services Work
```

---

# Summary — kube-proxy in This "Hard Way" Setup

* Runs on every worker node
* Uses certificate-based authentication
* Watches Services and Endpoints continuously
* Dynamically creates iptables rules
* Implements ClusterIP Services
* Implements NodePort Services
* Performs load balancing across backend pods
* Works together with kubelet, containerd, and CNI

## Final Mental Model

```text
Without kube-proxy:

Service Exists
      │
      ▼
Does Not Actually Work
```

```text
With kube-proxy:

Service Exists
      │
      ▼
iptables Rules Created
      │
      ▼
Traffic Reaches Pods
```

**kube-proxy is the component that turns the abstract concept of a Kubernetes Service into real, working network connectivity.**
