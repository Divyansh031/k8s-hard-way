# 🔐 Kubernetes The Hard Way — Certificates (Conceptual Guide)

## 📌 Overview

In this phase, we built the **security foundation of Kubernetes**.

Kubernetes is a **distributed system**, where multiple components communicate over the network.
To make this communication secure and trustworthy, we use **TLS certificates signed by a common Certificate Authority (CA)**.

---

# 🧠 Big Picture

All components in Kubernetes:

* Have an identity (certificate)
* Trust a common CA
* Verify each other before communicating

```text
            CA (Root of Trust)
                 │
     ┌───────────┼────────────┐
     │           │            │
  Admin      Worker       API Server
                              ▲
                              │
                  Scheduler & Controller
```

---

# 🔐 What is a Certificate Authority (CA)?

A **CA (Certificate Authority)** is a trusted entity that:

* Signs certificates
* Establishes trust between components

👉 If two components trust the same CA, they can trust each other.

---

# 📄 Understanding the Files

---

## ⚙️ `ca-config.json` → Rules

This file defines **how certificates should behave**.

### It controls:

* Expiry time
* Allowed usages (server auth, client auth, etc.)

👉 Think of it as:

> **Policy or rules for certificate creation**

---

## 📄 `csr.json` → Identity

CSR = Certificate Signing Request

Each component has its own CSR file.

### It defines:

* Who the component is (`CN`)
* What group it belongs to (`O`)

👉 Think of it as:

> **Identity proof submitted to the CA**

---

# 🔐 Certificates and Their Significance

---

## 1️⃣ CA Certificate (Root Trust)

### Purpose:

* Acts as the **root authority**
* Signs all other certificates

### Why it matters:

Without CA:

* No trust ❌
* No secure communication ❌

---

## 2️⃣ Admin Certificate

### Used by:

* Cluster administrator (you / kubectl)

### Purpose:

* Proves: *“I am an admin”*

### Communication:

```text
Admin → API Server
```

### What happens:

* API server verifies certificate
* Grants admin access

---

## 3️⃣ Worker Certificate

### Used by:

* Kubelet (on worker node)

### Purpose:

* Proves: *“I am worker-1”*

### Communication:

```text
Worker → API Server
```

### Why important:

* Allows node to join cluster
* Enables pod scheduling

### Without it:

* Node cannot register ❌
* Cluster becomes useless ❌

---

## 4️⃣ API Server Certificate (Most Important)

### Used by:

* Kubernetes API Server

### Purpose:

* Proves identity of API server

### Communication:

```text
All components → API Server
```

### Why special:

API server is accessed using:

* Node IP (192.168.56.10)
* Service IP (10.32.0.1)
* Hostname (controller-1)

👉 Certificate must include ALL of these

### Without it:

* TLS fails ❌
* No component can connect ❌

---

## 5️⃣ Controller Manager Certificate

### Used by:

* Controller Manager

### Purpose:

* Authenticates controller to API server

### Communication:

```text
Controller → API Server
```

### Role:

* Maintains cluster state
* Creates/updates resources

---

## 6️⃣ Scheduler Certificate

### Used by:

* Scheduler

### Purpose:

* Authenticates scheduler to API server

### Communication:

```text
Scheduler → API Server
```

### Role:

* Decides which node runs which pod

---

# ❓ Why Some Certificates Need Hostnames

### Rule:

* **Server components** → need hostname/IP in certificate
* **Client components** → do NOT need it

---

### Example:

| Component  | Role   | Needs Hostname? |
| ---------- | ------ | --------------- |
| API Server | Server | ✅ Yes           |
| Worker     | Client | ❌ No            |
| Scheduler  | Client | ❌ No            |
| Controller | Client | ❌ No            |

---

# 🔄 Communication Flow

```text
Worker → API Server
Scheduler → API Server
Controller → API Server
Admin → API Server
```

---

# 🔐 What Happens During Communication

Example: Worker → API Server

1. Worker sends its certificate

2. API Server verifies:

   * Is it signed by CA? ✅
   * Is identity valid? ✅

3. API Server responds with its certificate

4. Worker verifies API server

👉 Secure TLS connection established

---

# 🔥 Core Principle

```text
Every component:
- Has identity (certificate)
- Trusts CA
- Verifies others using CA
```

---

# ⚠️ What Can Go Wrong

| Issue            | Result               |
| ---------------- | -------------------- |
| Wrong CN         | Authentication fails |
| Missing hostname | TLS failure          |
| Wrong CA         | Trust failure        |

---

# 🧠 Final Mental Model

```text
          CA (Root Trust)
               │
   ┌───────────┼────────────┐
   │           │            │
 Admin      Worker      API Server
                           ▲
                           │
              Scheduler & Controller

All communication:
→ Verified using CA
→ Encrypted using TLS
```

---

# 🛠️ Certificate Generation Commands

All certificates in Kubernetes are generated using:

* CSR files (`*-csr.json`) → identity
* CA config (`ca-config.json`) → certificate rules
* CA certificate + key → trust authority

---

# ⚙️ Generate CA Certificate

```bash
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
```

This generates:

```text
ca.pem
ca-key.pem
ca.csr
```

---

# ⚙️ Generate Admin Certificate

```bash
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin
```

This generates:

```text
admin.pem
admin-key.pem
admin.csr
```

---

# ⚙️ Generate Worker Certificate

```bash
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=worker-1,192.168.56.11 \
  -profile=kubernetes \
  worker-1-csr.json | cfssljson -bare worker-1
```

This generates:

```text
worker-1.pem
worker-1-key.pem
worker-1.csr
```

---

# ⚙️ Generate API Server Certificate

```bash
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=10.32.0.1,192.168.56.10,127.0.0.1,controller-1,kubernetes.default \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes
```

This generates:

```text
kubernetes.pem
kubernetes-key.pem
kubernetes.csr
```

---

# ⚙️ Generate Controller Manager Certificate

```bash
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  controller-manager-csr.json | cfssljson -bare controller-manager
```

This generates:

```text
controller-manager.pem
controller-manager-key.pem
controller-manager.csr
```

---

# ⚙️ Generate Scheduler Certificate

```bash
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  scheduler-csr.json | cfssljson -bare scheduler
```

This generates:

```text
scheduler.pem
scheduler-key.pem
scheduler.csr
```

---

# ⚠️ Important Security Rule

Never upload these files publicly:

```text
*-key.pem
```

Especially:

```text
ca-key.pem
```

Because private keys are secret identities used for authentication and signing.

---


# ❌ Recommended `.gitignore`

```gitignore
*.pem
*.csr
```

This prevents accidentally pushing generated certificates or private keys to GitHub.

---

# 🧠 Important Engineering Concept

In real-world infrastructure:

```text
JSON files = source of truth
PEM/CSR files = generated artifacts
```

Generated artifacts should usually NOT be stored in Git repositories.

---


