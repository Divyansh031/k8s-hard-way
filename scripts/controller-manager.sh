#!/bin/bash

set -euxo pipefail

if systemctl is-active --quiet kube-controller-manager; then
  echo "✅ kube-controller-manager already running, skipping"
  exit 0
fi

# 1. Download binary
wget -q --show-progress \
  "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64/kube-controller-manager"
chmod +x kube-controller-manager
mv kube-controller-manager /usr/local/bin/

# 2. Create systemd unit
cat <<EOF > /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://kubernetes.io/docs

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --bind-address=0.0.0.0 \\
  --cluster-cidr=${POD_CIDR} \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/etc/kubernetes/pki/ca.pem \\
  --cluster-signing-key-file=/etc/kubernetes/pki/ca-key.pem \\
  --kubeconfig=/etc/kubernetes/config/controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/etc/kubernetes/pki/ca.pem \\
  --service-account-private-key-file=/etc/kubernetes/pki/service-account-key.pem \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 3. Start
systemctl daemon-reload
systemctl enable kube-controller-manager
systemctl start kube-controller-manager

sleep 3
systemctl is-active kube-controller-manager

echo "✅ kube-controller-manager running"