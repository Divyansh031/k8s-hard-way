#!/bin/bash

set -euxo pipefail

if systemctl is-active --quiet containerd; then
  echo "✅ containerd already running, skipping"
  exit 0
fi

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
wget  "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz"
tar -xvf containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz -C /usr/local
rm containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz

# 6. Install runc
wget -q "https://github.com/opencontainers/runc/releases/download/v1.2.3/runc.amd64"
chmod +x runc.amd64
mv runc.amd64 /usr/local/sbin/runc

# 7. Default containerd config
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# Use systemd cgroup driver (required for kubelet)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# 8. Systemd unit for containerd
wget -q "https://raw.githubusercontent.com/containerd/containerd/main/containerd.service" \
  -O /etc/systemd/system/containerd.service

systemctl daemon-reload
systemctl enable containerd
systemctl start containerd

sleep 2
systemctl is-active containerd

echo "✅ containerd running"