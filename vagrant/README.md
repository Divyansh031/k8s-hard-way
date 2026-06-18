# 🚀 Kubernetes The Hard Way — Infrastructure Setup Guide

This document explains the **core concepts and decisions** behind setting up the infrastructure using Vagrant for a Kubernetes cluster.

---

# 📦 What is Vagrant?

Vagrant is a tool used to **create and manage virtual machines using code**.

Instead of manually:

* Creating VMs
* Configuring networking
* Assigning resources

You define everything in a **Vagrantfile**, and run:

```bash
vagrant up
```

👉 Vagrant will automatically:

* Create machines
* Configure them
* Run setup scripts

### 🧠 Key Idea:

> Vagrant = Infrastructure as Code (IaC)

---

# 📦 What is a Box?

A **box** is a pre-built virtual machine image.

Example:

```ruby
config.vm.box = "ubuntu/jammy64"
```

This means:

* Use Ubuntu 22.04 as the base OS

### 🧠 Think of it like:

> A template OS that Vagrant uses to create machines

---

# 🌐 How did we choose IPs?

```ruby
"controller-1" => "192.168.56.10"
"worker-1"     => "192.168.56.11"
```

These IPs are:

* From **private IP range** (`192.168.x.x`)
* Used for **local communication only**
* Not accessible from the internet

### Why `192.168.56.x`?

* Commonly used by VirtualBox host-only networks

### Why `.10`, `.11`?

* No strict rule
* Just chosen to be:

  * Simple
  * Predictable
  * Easy to remember

### 🧠 Important:

> Fixed IPs ensure stable communication between nodes

---

# 🖥️ What is VirtualBox?

VirtualBox is a **virtualization software**.

### Role in Vagrant:

Vagrant itself does NOT create VMs.

Instead:

```text
Vagrant → VirtualBox → Virtual Machines
```

### What VirtualBox does:

* Runs virtual machines
* Allocates CPU and RAM
* Handles networking

---

# 🧠 Difference Between Memory (RAM) and CPU in VMs

In the Vagrantfile:

vb.memory = 1024

vb.cpus = 1


## 💾 Memory (RAM)

- Memory = RAM allocated to the VM
- Measured in MB
```👉 1024 MB = 1 GB```

### What it does:
- Stores running processes and data
- Required for OS + Kubernetes components
#### Example:

If your system has 8GB RAM:

2 VMs × 1GB each = 2GB used



## ⚙️ CPU
CPU = processing power allocated to the VM
Measured in number of cores

vb.cpus = 1

This means:

👉 Each VM gets 1 CPU core

---

### 🧠 What CPU does:
- Executes instructions
- Runs processes
- Handles computations

---
#### In simple terms:
#### RAM = memory (stores things)
#### CPU = brain (processes things)

---

# ⚙️ Understanding `scripts/common.sh`

This script prepares the machines for Kubernetes.

---

## 🔴 What is Swap?

Swap is:

> Disk space used as extra memory when RAM is full

### Problem:

* Slower than RAM
* Causes unpredictable performance

---

## ❌ What does `swapoff -a` do?

```bash
swapoff -a
```

* Disables swap immediately

---

## ❌ Why disable swap?

Kubernetes requires:

> Predictable memory behavior

If swap is enabled:

* OS may move memory to disk
* Kubernetes loses control

👉 So:

> Swap MUST be disabled for Kubernetes

---

## 📄 What is `/etc/hosts`?

This file maps:

```text
IP Address → Hostname
```

Example:

```bash
192.168.56.10 controller-1
192.168.56.11 worker-1
```

---

## 🧠 What does it do?

Allows you to use:

```bash
ping worker-1
```

Instead of:

```bash
ping 192.168.56.11
```

---

## ❓ Why is this important?

* Easier communication
* Required for internal services
* Helps in certificate validation later

---

# 🌐 What is IP Forwarding?

```bash
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
```

---

## 🔍 What does it do?

Enables the system to:

> Forward network packets between interfaces

---

## 🧠 Simple Meaning:

Without IP forwarding:

* Machine behaves like a normal device ❌

With IP forwarding:

* Machine behaves like a router ✅

---

## ❓ Why is it important for Kubernetes?

In Kubernetes:

* Pods communicate across nodes
* Network traffic must flow between machines

If IP forwarding is OFF:

* Packets get blocked
* Cluster networking fails

---

# 📁 Infrastructure Files

This phase is driven by three files:

```text
Vagrantfile
settings.yaml
scripts/common.sh
```

### Vagrantfile

Responsible for:

- Creating controller and worker VMs
- Assigning CPU and RAM
- Configuring networking
- Running provisioning scripts

### settings.yaml

Acts as the central configuration file.

Contains:

```yaml
network:
  control_ip:
  worker_ip:

software:
  box:
```

This allows infrastructure settings to be changed without modifying the Vagrantfile.

### scripts/common.sh

Executed automatically when VMs are provisioned.

Responsible for:

- Disabling swap
- Configuring /etc/hosts
- Enabling IP forwarding
- Installing common packages

---
# 🔥 Final Understanding

By setting up this infrastructure, we are:

* Creating multiple machines
* Enabling communication between them
* Preparing them for Kubernetes requirements

---

# 🧠 Key Takeaways

* Vagrant helps automate VM creation
* VirtualBox actually runs the VMs
* Static IPs ensure stable networking
* Swap must be disabled for Kubernetes
* `/etc/hosts` enables hostname-based communication
* IP forwarding allows network traffic between nodes

---


