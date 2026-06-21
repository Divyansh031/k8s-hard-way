# 🌐 CoreDNS — Kubernetes DNS Server

## Overview

**CoreDNS** is the **official DNS server** for Kubernetes. It provides **service discovery** and name resolution inside the cluster.

Instead of hardcoding IP addresses, pods and containers can use human-readable names such as:

```text
my-service.my-namespace.svc.cluster.local
```

or simply:

```text
my-service
```

CoreDNS translates these names into the correct ClusterIP or Pod IP.

---

# Why Do We Need DNS in Kubernetes?

In Kubernetes:

* Pods receive dynamic IP addresses
* Pods can be destroyed and recreated at any time
* Pod IPs are not stable
* Services provide stable virtual IPs

Applications need a reliable way to find each other.

Without DNS:

```text
Frontend → 10.200.1.5
Backend  → 10.200.2.8
Database → 10.200.1.12
```

Every IP change would require application reconfiguration.

With CoreDNS:

```text
frontend.default.svc.cluster.local
backend.default.svc.cluster.local
database.default.svc.cluster.local
```

Applications communicate using names instead of IP addresses.

---

# CoreDNS in This Repository

CoreDNS is deployed as a standard Kubernetes workload.

The deployment consists of:

* ServiceAccount
* ClusterRole
* ClusterRoleBinding
* ConfigMap
* Deployment
* Service

All resources run inside:

```text
kube-system
```

namespace.

---

## Key Characteristics

* Single replica (for simplicity)
* Runs on the control plane node
* Uses official image:

  ```text
  coredns/coredns:1.12.0
  ```
* DNS Service IP:

  ```text
  10.32.0.10
  ```
* Matches:

  ```text
  CLUSTER_DNS
  ```

  from `settings.yaml`

---

# How DNS Resolution Works

Suppose a pod wants to reach:

```text
nginx.default.svc.cluster.local
```

---

## Step 1 — Pod Queries DNS

Inside the pod:

```bash
nslookup nginx.default.svc.cluster.local
```

---

## Step 2 — Query Goes to `/etc/resolv.conf`

The pod's resolver contains:

```text
nameserver 10.32.0.10
```

This value comes from kubelet's:

```yaml
clusterDNS:
  - 10.32.0.10
```

configuration.

---

## Step 3 — Query Reaches CoreDNS

Traffic flow:

```text
Pod
 │
 ▼
10.32.0.10:53
 │
 ▼
CoreDNS
```

---

## Step 4 — CoreDNS Looks Up Kubernetes Resources

CoreDNS continuously watches:

* Services
* Endpoints
* EndpointSlices
* Pods
* Namespaces

using the Kubernetes API.

---

## Step 5 — CoreDNS Returns the Answer

Example:

```text
nginx.default.svc.cluster.local

↓

10.32.0.50
```

The application can now connect to the Service.

---

## Step 6 — External Domains

For:

```text
google.com
```

CoreDNS does not know the answer.

It forwards the request to upstream DNS servers:

```text
CoreDNS
   │
   ▼
Host Resolver
(/etc/resolv.conf)
   │
   ▼
Internet DNS
```

---

# Script Breakdown

The script deploys CoreDNS in five stages:

```text
1. RBAC
2. ConfigMap
3. Deployment
4. Service
5. Wait for Ready
```

---

# 1. RBAC Configuration

## ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
```

### Purpose

Creates an identity for CoreDNS.

Instead of running anonymously, CoreDNS authenticates as:

```text
system:serviceaccount:kube-system:coredns
```

---

## ClusterRole

```yaml
kind: ClusterRole
metadata:
  name: system:coredns
```

Defines what CoreDNS is allowed to access.

---

### Services Permission

```yaml
resources:
  - services
verbs:
  - list
  - watch
```

Why?

CoreDNS must know:

```text
Service Name
      ↓
ClusterIP
```

Example:

```text
nginx.default.svc.cluster.local
      ↓
10.32.0.50
```

---

### Endpoints Permission

```yaml
resources:
  - endpoints
verbs:
  - list
  - watch
```

Why?

CoreDNS needs backend pod information.

Example:

```text
Service
   ↓
Endpoints
   ↓
Pod IPs
```

---

### Pods Permission

```yaml
resources:
  - pods
verbs:
  - list
  - watch
```

Needed for pod-based DNS lookups.

Example:

```text
10-200-1-5.default.pod.cluster.local
```

---

### Namespaces Permission

```yaml
resources:
  - namespaces
verbs:
  - list
  - watch
```

Required to correctly build DNS records.

Example:

```text
service.default.svc.cluster.local
```

---

### Nodes Permission

```yaml
resources:
  - nodes
verbs:
  - get
```

Used by some Kubernetes DNS features and metadata lookups.

---

### EndpointSlices Permission

```yaml
apiGroups:
  - discovery.k8s.io
resources:
  - endpointslices
verbs:
  - list
  - watch
```

Modern Kubernetes stores endpoint information in EndpointSlices.

CoreDNS watches them to build DNS records efficiently.

---

## ClusterRoleBinding

```yaml
kind: ClusterRoleBinding
```

Connects:

```text
ServiceAccount
        ↓
ClusterRole
```

Meaning:

```text
coredns ServiceAccount
        ↓
gets permissions from
        ↓
system:coredns
```

Without this binding:

```text
CoreDNS starts
but cannot read cluster resources
```

---

# 2. ConfigMap — CoreDNS Configuration

This is the most important resource.

```yaml
kind: ConfigMap
metadata:
  name: coredns
```

Stores the CoreDNS configuration file:

```text
Corefile
```

---

# Understanding the Corefile

```text
.:53 {
    errors
    health {
      lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
      pods insecure
      fallthrough in-addr.arpa ip6.arpa
      ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
      max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}
```

---

## `.:53`

```text
.:53
```

Meaning:

```text
Listen on:
All Interfaces (.)
Port 53
```

Port 53 is the standard DNS port.

---

## `errors`

```text
errors
```

Logs DNS errors.

Example:

```text
NXDOMAIN
Timeout
Plugin Failure
```

Useful for troubleshooting.

---

## `health`

```text
health {
  lameduck 5s
}
```

Creates health endpoint:

```text
http://<pod-ip>:8080/health
```

---

### What is Lameduck?

```text
lameduck 5s
```

When shutting down:

```text
Stop accepting new traffic
Wait 5 seconds
Exit
```

Prevents dropped DNS requests during restarts.

---

## `ready`

```text
ready
```

Creates readiness endpoint:

```text
http://<pod-ip>:8181/ready
```

Kubernetes uses this endpoint in readiness probes.

---

## `kubernetes`

```text
kubernetes cluster.local in-addr.arpa ip6.arpa
```

This is the most important plugin.

It watches the Kubernetes API.

---

### `cluster.local`

Defines the cluster DNS domain.

Example:

```text
nginx.default.svc.cluster.local
```

---

### `in-addr.arpa`

Supports reverse DNS lookups for IPv4.

Example:

```bash
nslookup 10.32.0.50
```

---

### `ip6.arpa`

Supports reverse lookups for IPv6.

---

### `pods insecure`

```text
pods insecure
```

Allows Pod IP DNS lookups.

Example:

```text
10-200-1-5.default.pod.cluster.local
```

Without validating pod ownership.

Suitable for learning environments.

---

### `fallthrough`

```text
fallthrough in-addr.arpa ip6.arpa
```

If CoreDNS cannot answer:

```text
Reverse Lookup
```

it passes the request to the next plugin.

---

### `ttl 30`

```text
ttl 30
```

DNS records are cached for:

```text
30 seconds
```

before clients must query again.

---

## `prometheus`

```text
prometheus :9153
```

Exposes metrics:

```text
http://<pod-ip>:9153/metrics
```

Metrics include:

* DNS request count
* Latency
* Cache hits
* Cache misses

Useful for monitoring.

---

## `forward`

```text
forward . /etc/resolv.conf
```

Handles all non-Kubernetes queries.

Example:

```text
google.com
github.com
openai.com
```

Flow:

```text
Pod
 ↓
CoreDNS
 ↓
Host DNS
 ↓
Internet
```

---

### `max_concurrent 1000`

```text
max_concurrent 1000
```

Allows:

```text
1000 simultaneous forwarded queries
```

before throttling.

---

## `cache`

```text
cache 30
```

Caches DNS responses for:

```text
30 seconds
```

Benefits:

* Faster responses
* Reduced API calls
* Reduced external DNS traffic

---

## `loop`

```text
loop
```

Detects DNS forwarding loops.

Example:

```text
CoreDNS
  ↓
DNS Server
  ↓
CoreDNS
```

Without protection:

```text
Infinite recursion
```

This plugin prevents that.

---

## `reload`

```text
reload
```

Automatically reloads the Corefile when the ConfigMap changes.

No pod restart required.

---

## `loadbalance`

```text
loadbalance
```

Randomizes returned DNS records.

Example:

Without:

```text
10.200.1.2
10.200.1.3
10.200.1.4
```

always returned in the same order.

With loadbalance:

```text
10.200.1.4
10.200.1.2
10.200.1.3
```

Order changes per request.

Provides basic DNS-level load balancing.

---

# 3. Deployment

## Metadata

```yaml
metadata:
  name: coredns
  namespace: kube-system
```

Creates the CoreDNS deployment.

---

## Replicas

```yaml
replicas: 1
```

Only one CoreDNS pod runs.

Production clusters typically use:

```text
2+
```

replicas for high availability.

---

## ServiceAccount

```yaml
serviceAccountName: coredns
```

Uses the ServiceAccount created earlier.

---

## Toleration

```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
```

Allows scheduling on the controller node.

Normally workloads avoid control-plane nodes.

This toleration overrides that restriction.

---

## Container Image

```yaml
image: coredns/coredns:1.12.0
```

Official CoreDNS image.

---

## Arguments

```yaml
args:
  - "-conf"
  - "/etc/coredns/Corefile"
```

Tells CoreDNS where to find its configuration.

---

## Ports

### DNS UDP

```yaml
containerPort: 53
protocol: UDP
```

Primary DNS traffic.

---

### DNS TCP

```yaml
containerPort: 53
protocol: TCP
```

Used for:

* Large DNS responses
* Zone transfers
* TCP fallback

---

### Metrics

```yaml
containerPort: 9153
```

Prometheus metrics endpoint.

---

## Volume Mount

```yaml
volumeMounts:
  - mountPath: /etc/coredns
```

Mounts the ConfigMap.

Result:

```text
ConfigMap
     ↓
/etc/coredns/Corefile
```

---

## Liveness Probe

```yaml
livenessProbe:
```

Checks:

```text
/health
```

If unhealthy:

```text
Kubernetes restarts CoreDNS
```

---

## Readiness Probe

```yaml
readinessProbe:
```

Checks:

```text
/ready
```

Only receives traffic when ready.

---

## Volumes

```yaml
volumes:
  - configMap:
      name: coredns
```

Makes the Corefile available inside the container.

---

# 4. Service — kube-dns

```yaml
kind: Service
metadata:
  name: kube-dns
```

This is one of the most important resources.

---

## ClusterIP

```yaml
clusterIP: 10.32.0.10
```

Must match:

```text
CLUSTER_DNS
```

and kubelet's:

```yaml
clusterDNS:
  - 10.32.0.10
```

configuration.

---

## Selector

```yaml
selector:
  k8s-app: kube-dns
```

Connects the Service to CoreDNS pods.

---

## Ports

### UDP

```yaml
port: 53
protocol: UDP
```

Standard DNS.

---

### TCP

```yaml
port: 53
protocol: TCP
```

Large DNS responses.

---

# Complete DNS Request Flow

```text
Application
     │
     ▼
Pod Resolver
(/etc/resolv.conf)
     │
     ▼
10.32.0.10
(kube-dns Service)
     │
     ▼
kube-proxy
     │
     ▼
CoreDNS Pod
     │
     ├──────── Kubernetes Query
     │                │
     │                ▼
     │          API Server
     │
     └──────── External Query
                      │
                      ▼
               Upstream DNS
```

---

# Verification Commands

## Check Deployment

```bash
kubectl get deployment coredns -n kube-system
```

---

## Check Pods

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

---

## Check Service

```bash
kubectl get svc kube-dns -n kube-system
```

---

## Check ConfigMap

```bash
kubectl get configmap coredns -n kube-system -o yaml
```

---

## Check Logs

```bash
kubectl logs -n kube-system -l k8s-app=kube-dns
```

---

## Test Internal DNS

```bash
kubectl run test \
  --image=busybox \
  -it \
  --rm -- sh
```

Inside the pod:

```bash
nslookup kubernetes.default.svc.cluster.local
```

---

## Test External DNS

```bash
nslookup google.com
```

---

# Position in the Kubernetes Stack

```text
etcd + API Server
        │
        ▼
Stores Cluster State

kubelet + containerd + CNI
        │
        ▼
Runs Pods

kube-proxy
        │
        ▼
Makes Services Reachable

CoreDNS
        │
        ▼
Makes Services Reachable By Name
```

---

# Summary — CoreDNS in This Hard Way Setup

* Provides internal service discovery
* Converts names into Service IPs
* Watches Kubernetes resources dynamically
* Uses RBAC permissions to access cluster state
* Runs as a standard Deployment
* Exposes DNS through the `kube-dns` Service
* Uses ClusterIP `10.32.0.10`
* Forwards external DNS queries to upstream resolvers
* Forms the foundation of service-to-service communication

Without CoreDNS, every application would need to communicate using raw IP addresses, which is impractical in a dynamic Kubernetes environment.

**CoreDNS completes the service discovery layer of the cluster.**
