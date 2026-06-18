# Kubernetes The Hard Way (Automated with Vagrant)

A hands-on implementation of Kubernetes from scratch inspired by Kubernetes The Hard Way.

The goal of this project is not simply to create a working cluster, but to understand how Kubernetes components communicate internally, how TLS authentication works, how cluster state is stored, and how the control plane is assembled piece by piece.

---

# Project Goals

This repository focuses on learning the internals of Kubernetes by manually building each layer of the cluster.

Topics covered:

* Infrastructure provisioning
* Linux fundamentals
* Kubernetes networking
* Public Key Infrastructure (PKI)
* TLS certificates
* Client authentication
* Kubeconfig generation
* etcd installation and configuration
* Systemd service management
* Kubernetes control plane architecture

---

# Architecture

Current cluster:

```text
                   +----------------+
                   |   controller-1 |
                   | 192.168.56.10  |
                   +--------+-------+
                            |
                            |
                    Kubernetes API
                            |
                            |
                   +--------+-------+
                   |    worker-1    |
                   | 192.168.56.11  |
                   +----------------+
```

---

# Repository Structure

```text
.
├── certs
│   ├── *.json
│   ├── generated/
│   └── README.md
│
├── kubeconfigs
│   ├── generated/
│   └── README.md
│
├── etcd
│   └── README.md
│
├── scripts
│   ├── common.sh
│   ├── certs.sh
│   ├── kubeconfigs.sh
│   └── etcd.sh
│
├── vagrant
│   └── README.md
│
│── README.md
├── settings.yaml
└── Vagrantfile
```

---

# Project Progress

## Phase 1 - Infrastructure

Completed:

* Vagrant setup
* VirtualBox networking
* Static IP configuration
* Hostname configuration
* Swap disabled
* IP forwarding enabled

Documentation:

```text
vagrant/README.md
```

---

## Phase 2 - Certificates

Completed:

* Certificate Authority (CA)
* Admin certificate
* Worker certificate
* API Server certificate
* Scheduler certificate
* Controller Manager certificate
* etcd certificate

Documentation:

```text
certs/README.md
```

---

## Phase 3 - Kubeconfigs

Completed:

* worker-1.kubeconfig
* controller-manager.kubeconfig
* scheduler.kubeconfig
* admin.kubeconfig

Documentation:

```text
kubeconfigs/README.md
```

---

## Phase 4 - etcd

Completed:

* etcd installation
* TLS configuration
* systemd service
* health verification

Documentation:

```text
etcd/README.md
```

---

# Learning Outcomes

After completing this project you should understand:

* How Kubernetes components authenticate
* Why certificates are required
* How kubeconfigs work
* How cluster state is stored
* Why etcd is critical
* How Linux services are managed
* How control plane components communicate

---

# Important Security Note

Generated artifacts should never be committed:

```gitignore
*.pem
*.csr
*.kubeconfig
```

Especially:

```text
ca-key.pem
```

The CA private key is the root trust of the cluster.

---


