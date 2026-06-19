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
├── certs
│   ├── admin-csr.json
│   ├── ca-config.json
│   ├── ca-csr.json
│   ├── controller-manager-csr.json
│   ├── etcd-csr.json
│   ├── generated
│   │   ├── admin.csr
│   │   ├── admin-key.pem
│   │   ├── admin.pem
│   │   ├── ca.csr
│   │   ├── ca-key.pem
│   │   ├── ca.pem
│   │   ├── controller-manager.csr
│   │   ├── controller-manager-key.pem
│   │   ├── controller-manager.pem
│   │   ├── etcd.csr
│   │   ├── etcd-key.pem
│   │   ├── etcd.pem
│   │   ├── kubernetes.csr
│   │   ├── kubernetes-key.pem
│   │   ├── kubernetes.pem
│   │   ├── scheduler.csr
│   │   ├── scheduler-key.pem
│   │   ├── scheduler.pem
│   │   ├── service-account.csr
│   │   ├── service-account-key.pem
│   │   ├── service-account.pem
│   │   ├── worker-1.csr
│   │   ├── worker-1-csr.json
│   │   ├── worker-1-key.pem
│   │   └── worker-1.pem
│   ├── kubernetes-csr.json
│   ├── README.md
│   ├── scheduler-csr.json
│   └── service-account-csr.json
├── control-plane
│   ├── api-server
│   │   └── README.md
│   ├── controller-manager
│   │   └── README.md
│   ├── etcd
│   │   └── README.md
│   ├── rbac
│   │   └── README.md
│   └── scheduler
│       └── README.md
├── kubeconfigs
│   ├── generated
│   │   ├── admin.kubeconfig
│   │   ├── controller-manager.kubeconfig
│   │   ├── scheduler.kubeconfig
│   │   └── worker-1.kubeconfig
│   └── README.md
├── README.md
├── scripts
│   ├── api-server.sh
│   ├── certs.sh
│   ├── common.sh
│   ├── controller-manager.sh
│   ├── control-plane-setup.sh
│   ├── etcd.sh
│   ├── kubeconfigs.sh
│   ├── rbac.sh
│   └── scheduler.sh
├── settings.yaml
├── struct.txt
├── vagrant
│   └── README.md
└── Vagrantfile
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


