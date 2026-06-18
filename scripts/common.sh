#!/bin/bash

set -euxo pipefail

# Skip if already provisioned
if command -v kubectl &>/dev/null && command -v cfssl &>/dev/null; then
  echo "✅ common.sh already provisioned, skipping"
  exit 0
fi

# Update system
apt-get update -y

# Install basic tools
apt-get install -y curl wget net-tools 

# Install kubectl
curl -LO "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install cfssl + cfssljson (they are not in apt)
echo "Installing cfssl and cfssljson..."
CFSSL_VERSION="1.6.5"
curl -L "https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssl_${CFSSL_VERSION}_linux_amd64" -o /usr/local/bin/cfssl
curl -L "https://github.com/cloudflare/cfssl/releases/download/v${CFSSL_VERSION}/cfssljson_${CFSSL_VERSION}_linux_amd64" -o /usr/local/bin/cfssljson

chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson

# Verify
cfssl version
cfssljson -version

# Disable swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p