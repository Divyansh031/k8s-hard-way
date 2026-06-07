# 🔐 Kubernetes The Hard Way — Kubeconfigs

## 📌 Overview

In this phase, we generated Kubernetes kubeconfig files for different cluster components. Kubeconfig files are extremely important because they define:

* **Which cluster** to connect to
* **Who** the client is
* **How** the client authenticates
* **Which Certificate Authority (CA)** to trust

Without kubeconfigs, Kubernetes components would not know where the API server is, how to securely authenticate, or which certificates to use.

---

## 🧠 Big Picture

Every Kubernetes component communicates through the API Server. To communicate securely, components need:

* ✅ API server address
* ✅ Trusted CA certificate
* ✅ Client certificate + key
* ✅ User/context information

All of this is bundled inside the **kubeconfig file**.

### 🔥 Mental Model

> **Kubeconfig** = (Cluster Information + Authentication Information + Context Information)

---

## 🧠 Why Kubeconfigs Exist

Instead of passing many flags manually like `--server`, `--client-certificate`, `--client-key`, and `--certificate-authority`, Kubernetes stores everything in one structured file (e.g., `worker-1.kubeconfig`). This makes authentication **portable and standardized**.

### 🔐 Kubernetes Client Authentication Flow

1. **Component** reads kubeconfig.
2. **Gets:** API Server Address, CA Certificate, Client Certificate, and Client Private Key.
3. **Connects** securely to API Server.
4. **API Server** verifies certificate using CA.
5. **Trusted communication** established.

---

## 📄 What a Kubeconfig Internally Contains

A kubeconfig contains 3 major sections:

1. **Cluster:** Defines API server address and trusted CA certificate.
2. **User:** Defines client certificate and private key.
3. **Context:** Connects the **User** + **Cluster**.

### 🧠 Why API Server Trusts Clients

Because all client certificates were signed using the same CA: `ca.pem`. The API server verifies:

* ✅ Is certificate signed by trusted CA?
* ✅ Is client identity valid?

---

## 🔐 Why Every Component Needs Its Own Kubeconfig

Every component has a different identity and responsibility.

| File | Used By | Purpose | Communication |
| --- | --- | --- | --- |
| **worker-1.kubeconfig** | Kubelet (Worker) | Authenticates worker node to API server | Worker → API Server |
| **controller-manager.kubeconfig** | Kube Controller Manager | Updates cluster state through API server | Controller Manager → API Server |
| **scheduler.kubeconfig** | Kube Scheduler | Watches unscheduled pods and assigns nodes | Scheduler → API Server |
| **admin.kubeconfig** | kubectl / Admin | Full administrative access to cluster | Admin → API Server |

---

## 🛠️ Installing kubectl

Inside the controller VM, run the following:

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
# Verify installation:
kubectl version --client

```

---

## ⚙️ Generating Kubeconfigs

All kubeconfigs were initially generated inside `/vagrant/certs` (where the certificates existed) and later moved to `/vagrant/kubeconfigs/generated` for a clean structure.

### 🔥 Worker Node Kubeconfig

```bash
# Set Cluster
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://192.168.56.10:6443 \
  --kubeconfig=worker-1.kubeconfig

# Set Credentials
kubectl config set-credentials system:node:worker-1 \
  --client-certificate=worker-1.pem \
  --client-key=worker-1-key.pem \
  --embed-certs=true \
  --kubeconfig=worker-1.kubeconfig

# Set Context
kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:node:worker-1 \
  --kubeconfig=worker-1.kubeconfig

# Use Context
kubectl config use-context default \
  --kubeconfig=worker-1.kubeconfig

```

### 🔥 Controller Manager Kubeconfig

```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://192.168.56.10:6443 \
  --kubeconfig=controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=controller-manager.pem \
  --client-key=controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=controller-manager.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-controller-manager \
  --kubeconfig=controller-manager.kubeconfig

kubectl config use-context default \
  --kubeconfig=controller-manager.kubeconfig

```

### 🔥 Scheduler Kubeconfig

```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://192.168.56.10:6443 \
  --kubeconfig=scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=scheduler.pem \
  --client-key=scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=scheduler.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-scheduler \
  --kubeconfig=scheduler.kubeconfig

kubectl config use-context default \
  --kubeconfig=scheduler.kubeconfig

```

### 🔥 Admin Kubeconfig

```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=https://192.168.56.10:6443 \
  --kubeconfig=admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem \
  --embed-certs=true \
  --kubeconfig=admin.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --kubeconfig=admin.kubeconfig

kubectl config use-context default \
  --kubeconfig=admin.kubeconfig

```

---

## 🔐 Why We Do NOT Push Kubeconfigs Publicly

Kubeconfig files contain embedded certificates, private keys, and cluster access credentials. If exposed publicly, **anyone can authenticate to and compromise the cluster.**



---


### 🔥 Final Mental Model

* **Kubeconfig**
* **Cluster Info:** API Server Address
* **Trust Info:** CA Certificate
* **Identity Info:** Client Certificate + Key
* **Context:** Which user talks to which cluster