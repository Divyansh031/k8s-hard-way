#!/bin/bash

set -euxo pipefail

if [ -f /opt/cni/bin/bridge ]; then
  echo "✅ CNI plugins already installed, skipping"
  exit 0
fi

# 1. Install CNI plugins
mkdir -p /opt/cni/bin
wget -q "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz"
tar -xvf cni-plugins-linux-amd64-${CNI_VERSION}.tgz -C /opt/cni/bin/
rm cni-plugins-linux-amd64-${CNI_VERSION}.tgz

# 2. Create CNI network config (bridge network per node)
mkdir -p /etc/cni/net.d

cat <<EOF > /etc/cni/net.d/10-bridge.conf
{
  "cniVersion": "0.4.0",
  "name": "bridge",
  "type": "bridge",
  "bridge": "cnio0",
  "isGateway": true,
  "ipMasq": true,
  "ipam": {
    "type": "host-local",
    "ranges": [[{"subnet": "${POD_CIDR_NODE}"}]],
    "routes": [{"dst": "0.0.0.0/0"}]
  }
}
EOF

cat <<EOF > /etc/cni/net.d/99-loopback.conf
{
  "cniVersion": "0.4.0",
  "name": "lo",
  "type": "loopback"
}
EOF

echo "✅ CNI plugins installed"