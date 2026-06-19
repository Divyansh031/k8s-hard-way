#!/bin/bash

set -euxo pipefail

if systemctl is-active --quiet kube-apiserver; then
  echo "✅ kube-apiserver already running, skipping"
  exit 0
fi

# 1. Download binary
wget -q --show-progress \
  "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64/kube-apiserver"
chmod +x kube-apiserver
mv kube-apiserver /usr/local/bin/

# 2. Create systemd unit
cat <<EOF > /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://kubernetes.io/docs

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${CONTROLLER_IP} \\
  --allow-privileged=true \\
  --authorization-mode=Node,RBAC \\
  --client-ca-file=/etc/kubernetes/pki/ca.pem \\
  --enable-admission-plugins=NodeRestriction \\
  --etcd-cafile=/etc/etcd/ca.pem \\
  --etcd-certfile=/etc/etcd/etcd.pem \\
  --etcd-keyfile=/etc/etcd/etcd-key.pem \\
  --etcd-servers=https://127.0.0.1:2379 \\
  --event-ttl=1h \\
  --kubelet-certificate-authority=/etc/kubernetes/pki/ca.pem \\
  --kubelet-client-certificate=/etc/kubernetes/pki/kubernetes.pem \\
  --kubelet-client-key=/etc/kubernetes/pki/kubernetes-key.pem \\
  --runtime-config=api/all=true \\
  --service-account-key-file=/etc/kubernetes/pki/service-account.pem \\
  --service-account-signing-key-file=/etc/kubernetes/pki/service-account-key.pem \\
  --service-account-issuer=https://${CONTROLLER_IP}:6443 \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --tls-cert-file=/etc/kubernetes/pki/kubernetes.pem \\
  --tls-private-key-file=/etc/kubernetes/pki/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 3. Start
systemctl daemon-reload
systemctl enable kube-apiserver
systemctl start kube-apiserver

sleep 3
systemctl is-active kube-apiserver

echo "✅ kube-apiserver running"