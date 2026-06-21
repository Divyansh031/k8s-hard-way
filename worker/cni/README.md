# 🌐 CNI (Container Network Interface) — Networking Layer

## Overview

**CNI (Container Network Interface)** is the **standard plugin interface** for Kubernetes networking.

Kubernetes itself does **not** include built-in networking. Instead, it delegates all pod networking responsibilities to a **CNI plugin**. The kubelet calls the CNI plugin whenever a pod is created or destroyed.

### What CNI Handles

* Assigning IP addresses to pods
* Creating network interfaces inside the pod's network namespace
* Setting up routing so pods can communicate
* NAT/masquerading for traffic going outside the cluster
* (In advanced plugins) Encryption, overlay networks, policy enforcement, etc.

---

# CNI in This Repository

* Installed **only on worker nodes** via `scripts/cni.sh`
* Uses the official **containernetworking/plugins** (v1.9.1)
* Implements a **simple bridge network** (not a full overlay like Calico or Flannel)
* Each worker node gets its own pod subnet:

  * `worker-1` → `10.200.1.0/24`
  * `worker-2` → `10.200.2.0/24`
  * Additional workers follow the same pattern

This is a **minimal viable networking setup** designed to help understand Kubernetes networking internals.

---

# How CNI Fits Into Kubernetes

When a pod is scheduled onto a worker node:

```text
API Server
     │
     ▼
  kubelet
     │
     ▼
 Calls CNI
     │
     ▼
 Creates Pod Network
     │
     ├── Creates Network Namespace
     ├── Creates veth Pair
     ├── Connects veth to Bridge
     ├── Assigns Pod IP
     └── Configures Routes
```

Without CNI, containers would start but would not have usable networking.

---

# CNI Configuration Files

Located in:

```bash
/etc/cni/net.d/
```

---

## 1. Main Network Configuration (`10-bridge.conf`)

```json
{
  "cniVersion": "0.4.0",
  "name": "bridge",
  "type": "bridge",
  "bridge": "cnio0",
  "isGateway": true,
  "ipMasq": true,
  "ipam": {
    "type": "host-local",
    "ranges": [[{"subnet": "10.200.1.0/24"}]],
    "routes": [{"dst": "0.0.0.0/0"}]
  }
}
```

### Detailed Explanation of Every Field

#### `cniVersion`

```json
"cniVersion": "0.4.0"
```

Specifies which CNI specification version this configuration follows.

---

#### `name`

```json
"name": "bridge"
```

Logical name of the network.

The kubelet uses this name when referring to the network.

---

#### `type`

```json
"type": "bridge"
```

Tells CNI to use the **bridge plugin**.

The bridge plugin creates a Linux bridge and connects pod interfaces to it.

---

#### `bridge`

```json
"bridge": "cnio0"
```

Creates (or reuses) a Linux bridge named:

```bash
cnio0
```

Think of it as a virtual network switch connecting all pod interfaces on that worker node.

Example:

```text
Pod A
  │
  ├── veth
  │
Pod B
  │
  ├── veth
  │
Pod C
  │
  └── veth

      ↓

    cnio0
```

Pods on the same node communicate through this bridge.

---

#### `isGateway`

```json
"isGateway": true
```

Makes the bridge act as the default gateway.

Example:

```text
Pod IP:       10.200.1.2
Gateway IP:   10.200.1.1
```

Any traffic leaving the pod first goes to the bridge.

---

#### `ipMasq`

```json
"ipMasq": true
```

Enables IP masquerading (NAT).

This allows pod traffic to reach external networks.

Example:

```text
Pod IP:       10.200.1.2
Destination:  8.8.8.8

↓

Source IP rewritten to worker node IP

↓

Internet
```

Without masquerading, external networks would not know how to return traffic to pod IPs.

---

## IP Address Management (IPAM)

### Type

```json
"type": "host-local"
```

Uses the Host Local IPAM plugin.

This plugin stores IP allocations locally on each worker node.

No external DHCP server is required.

---

### Pod Subnet

```json
"subnet": "10.200.1.0/24"
```

Defines the pod CIDR for this worker.

Example allocations:

```text
10.200.1.2
10.200.1.3
10.200.1.4
...
```

Each new pod receives the next available address.

---

### Default Route

```json
"routes": [
  {
    "dst": "0.0.0.0/0"
  }
]
```

Creates:

```bash
default via <bridge-gateway>
```

inside the pod.

Meaning:

```text
Any unknown destination
       ↓
    Send to bridge
```

---

## 2. Loopback Configuration (`99-loopback.conf`)

```json
{
  "cniVersion": "0.4.0",
  "name": "lo",
  "type": "loopback"
}
```

### Why This Exists

Every network namespace requires a loopback interface:

```text
127.0.0.1
```

Without it:

```bash
curl localhost
```

would fail inside containers.

---

### Field Explanation

#### `cniVersion`

```json
"cniVersion": "0.4.0"
```

Uses CNI specification version 0.4.0.

---

#### `name`

```json
"name": "lo"
```

Logical name of the loopback network.

---

#### `type`

```json
"type": "loopback"
```

Uses the loopback plugin.

The plugin simply ensures:

```bash
lo
```

exists and is UP inside the pod namespace.

Example:

```bash
ip addr show lo
```

Output:

```text
127.0.0.1/8
```

Many applications rely on localhost communication, so this plugin is mandatory.

---

# Pod Networking Establishment (Step by Step)

When kubelet starts a new pod:

### 1. Kubelet Calls the CNI Plugin

Kubelet passes:

* Pod name
* Namespace
* Container ID
* Network configuration

---

### 2. Bridge Plugin Executes

The bridge plugin:

* Creates (or reuses) `cnio0`
* Creates a veth pair

Example:

```text
Pod Namespace
┌─────────────┐
│ eth0        │
└──────┬──────┘
       │
       │ veth pair
       │
┌──────▼──────┐
│ cnio0       │
└─────────────┘
```

One end remains inside the pod.

The other end connects to the bridge.

---

### 3. IP Address Allocation

Host-local IPAM assigns:

```text
10.200.1.2/24
```

to the pod.

---

### 4. Route Configuration

Inside the pod:

```bash
ip route
```

Example:

```text
default via 10.200.1.1
10.200.1.0/24 dev eth0
```

---

### 5. Pod Becomes Reachable

The pod can now:

* Talk to other pods on the same node
* Reach services
* Reach external destinations

---

# Cross-Node Pod Communication

Pods on the same worker communicate directly through:

```text
veth → cnio0 → veth
```

However, this repository does **not** deploy an overlay network such as:

* Calico
* Flannel
* Cilium

Therefore cross-node communication is not automatically configured.

---

## How Cross-Node Communication Could Work Here

For pod-to-pod communication across workers, each node would require routes to every other pod CIDR.

Example:

### On worker-1

```bash
ip route add 10.200.2.0/24 via 192.168.56.12
```

### On worker-2

```bash
ip route add 10.200.1.0/24 via 192.168.56.11
```

Meaning:

```text
Traffic for 10.200.2.0/24
        ↓
Send to worker-2
```

and vice versa.

---

### Important Note

This routing is **not automatically configured** by the current scripts.

Although kube-proxy manages Service networking and load balancing, it does **not** establish pod-to-pod routes between nodes when using this simple bridge setup.

Production CNIs such as Calico, Flannel, and Cilium automatically distribute these routes.

---

# Key Components Involved

| Component              | Role                               |
| ---------------------- | ---------------------------------- |
| kubelet                | Calls CNI when creating pods       |
| bridge plugin          | Creates bridge networking          |
| host-local IPAM        | Assigns pod IPs                    |
| loopback plugin        | Creates localhost interface        |
| Linux bridge (`cnio0`) | Connects all local pods            |
| veth pairs             | Virtual cable between host and pod |

---

# Verification Commands

## Check CNI Configuration

```bash
ls /etc/cni/net.d/
cat /etc/cni/net.d/10-bridge.conf
cat /etc/cni/net.d/99-loopback.conf
```

---

## Check Bridge

```bash
ip link show cnio0
brctl show cnio0
```

---

## Check Interfaces

```bash
ip addr show
```

---

## Check Routing

```bash
ip route
```

---

## Check kubelet Logs

```bash
journalctl -u kubelet -n 100 | grep cni
```

---

# Limitations of This Setup

* No overlay network
* No automatic cross-node routing
* No encryption between nodes
* No advanced IP management
* No NetworkPolicy support
* Designed for learning Kubernetes internals

This makes the networking simple enough to understand while still exposing the core Kubernetes networking concepts.

---

# Communication Matrix

| Communication Type          | Works Out-of-Box?  | Notes                     |
| --------------------------- | ------------------ | ------------------------- |
| Pod ↔ Pod (same node)       | Yes                | Bridge + veth             |
| Pod → Service (ClusterIP)   | Mostly Yes         | kube-proxy iptables rules |
| Pod → External              | Yes                | ipMasq + IP forwarding    |
| Pod ↔ Pod (different nodes) | No (not automatic) | Missing inter-node routes |

---

# Summary

CNI is the **pluggable networking layer** of Kubernetes.

In this repository:

* We use the **bridge plugin** to create pod networking.
* Pods receive IPs from per-node subnets (`10.200.x.0/24`).
* A Linux bridge (`cnio0`) connects all local pods.
* Host-local IPAM assigns pod IP addresses.
* The loopback plugin provides localhost functionality.
* Communication relies heavily on Linux networking primitives:

  * Bridges
  * veth pairs
  * Routing tables
  * NAT
  * IP forwarding

This setup provides a clear view of the absolute minimum networking components required for Kubernetes pods to have network identity and connectivity.
