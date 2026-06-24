#!/bin/bash

set -euxo pipefail

if systemctl is-active --quiet kube-proxy; then
  echo "✅ kube-proxy already running, skipping"
  exit 0
fi

CONFIGS="/vagrant/kubeconfigs/generated"

# 1. Download binary
wget -q "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64/kube-proxy"
chmod +x kube-proxy
mv kube-proxy /usr/local/bin/

# 2. Copy kubeconfig
mkdir -p /var/lib/kube-proxy
cp ${CONFIGS}/kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig

# 3. Config file
NODE_IP=$(ip addr show | grep 'inet 192\.168\.56\.' | awk '{print $2}' | cut -d'/' -f1)

cat <<EOF > /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: /var/lib/kube-proxy/kubeconfig
mode: iptables
clusterCIDR: ${POD_CIDR}
nodePortAddresses:
    - "${NODE_IP}/24"   
EOF

# 4. Systemd unit
cat <<EOF > /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes.io/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kube-proxy
systemctl start kube-proxy

sleep 3
systemctl is-active kube-proxy

echo "✅ kube-proxy running"