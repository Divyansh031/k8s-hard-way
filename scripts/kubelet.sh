#!/bin/bash

set -euxo pipefail

if systemctl is-active --quiet kubelet; then
  echo "✅ kubelet already running, skipping"
  exit 0
fi

CERTS="/vagrant/certs/generated"
CONFIGS="/vagrant/kubeconfigs/generated"
HOSTNAME=$(hostname)

# 1. Download kubelet binary
wget -q "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64/kubelet"
chmod +x kubelet
mv kubelet /usr/local/bin/

# 2. Create directories
mkdir -p /var/lib/kubelet /var/lib/kubernetes /var/run/kubernetes

# 3. Copy certs and kubeconfig
cp ${CERTS}/${HOSTNAME}.pem     /var/lib/kubelet/
cp ${CERTS}/${HOSTNAME}-key.pem /var/lib/kubelet/
cp ${CERTS}/ca.pem              /var/lib/kubernetes/
cp ${CONFIGS}/${HOSTNAME}.kubeconfig /var/lib/kubelet/kubeconfig

# 4. Kubelet config file
cat <<EOF > /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: /var/lib/kubernetes/ca.pem
authorization:
  mode: Webhook
clusterDomain: cluster.local
clusterDNS:
  - ${CLUSTER_DNS}
podCIDR: ${POD_CIDR_NODE}
resolvConf: /run/systemd/resolve/resolv.conf
runtimeRequestTimeout: "15m"
tlsCertFile: /var/lib/kubelet/${HOSTNAME}.pem
tlsPrivateKeyFile: /var/lib/kubelet/${HOSTNAME}-key.pem
cgroupDriver: systemd
EOF

# 5. Systemd unit
cat <<EOF > /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes.io/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

sleep 3
systemctl is-active kubelet

echo "✅ kubelet running"