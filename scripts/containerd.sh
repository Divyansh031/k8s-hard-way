#!/bin/bash

set -euxo pipefail

if ! systemctl is-active --quiet containerd; then

  # 1. Install dependencies
  apt-get update -y
  apt-get install -y apt-transport-https ca-certificates socat conntrack ipset

  # 2. Disable swap
  swapoff -a

  # 3. Load required kernel modules
  modprobe overlay
  modprobe br_netfilter

  cat <<EOF > /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

  # 4. Kernel settings for networking
  cat <<EOF > /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
  sysctl --system

  # 5. Download and install containerd
  wget "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz"
  tar -xvf containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz -C /usr/local
  rm containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz

  # 6. Install runc
  wget -q "https://github.com/opencontainers/runc/releases/download/v1.2.3/runc.amd64"
  chmod +x runc.amd64
  mv runc.amd64 /usr/local/sbin/runc

  # 7. Default containerd config
  mkdir -p /etc/containerd
  containerd config default > /etc/containerd/config.toml
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  sed -i "s|config_path = ''|config_path = '/etc/containerd/certs.d'|" /etc/containerd/config.toml

  # 8. Systemd unit for containerd
  wget -q "https://raw.githubusercontent.com/containerd/containerd/main/containerd.service" \
    -O /etc/systemd/system/containerd.service

  systemctl daemon-reload
  systemctl enable containerd
  systemctl start containerd

  sleep 2
  systemctl is-active containerd

fi

# Always run — safe to apply every time (idempotent)
# Configure insecure registry for local Docker registry pod
NODE_IP=$(ip addr show | grep 'inet 192\.168\.56\.' | awk '{print $2}' | cut -d'/' -f1)
REGISTRY="${NODE_IP}:30500"

mkdir -p /etc/containerd/certs.d/${REGISTRY}
cat <<EOF > /etc/containerd/certs.d/${REGISTRY}/hosts.toml
server = "http://${REGISTRY}"

[host."http://${REGISTRY}"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF

# Restart containerd to pick up registry config
systemctl restart containerd
sleep 2
systemctl is-active containerd

echo "✅ containerd running"