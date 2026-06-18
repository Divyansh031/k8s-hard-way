#!/bin/bash

set -euxo pipefail

CERTS_SRC="/vagrant/certs/generated"

# 1. Download and install etcd
wget -q "https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz"
tar -xvf etcd-${ETCD_VERSION}-linux-amd64.tar.gz
mv etcd-${ETCD_VERSION}-linux-amd64/etcd* /usr/local/bin/
rm -rf etcd-${ETCD_VERSION}-linux-amd64 etcd-${ETCD_VERSION}-linux-amd64.tar.gz

# Verify
etcd --version

# 2. Create directories
mkdir -p /etc/etcd /var/lib/etcd
chmod 700 /var/lib/etcd

# 3. Copy certs
cp ${CERTS_SRC}/ca.pem \    
   ${CERTS_SRC}/etcd.pem \
   ${CERTS_SRC}/etcd-key.pem \
   /etc/etcd/

# 4. Create systemd unit
cat <<EOF > /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/etcd-io/etcd

[Service]
ExecStart=/usr/local/bin/etcd \\
  --name controller-1 \\
  --cert-file=/etc/etcd/etcd.pem \\
  --key-file=/etc/etcd/etcd-key.pem \\
  --peer-cert-file=/etc/etcd/etcd.pem \\
  --peer-key-file=/etc/etcd/etcd-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${CONTROLLER_IP}:2380 \\
  --listen-peer-urls https://${CONTROLLER_IP}:2380 \\
  --listen-client-urls https://${CONTROLLER_IP}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://${CONTROLLER_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster controller-1=https://${CONTROLLER_IP}:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 5. Start etcd
systemctl daemon-reload
systemctl enable etcd
systemctl start etcd

# 6. Verify health
sleep 3
ETCDCTL_API=3 etcdctl \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/etcd.pem \
  --key=/etc/etcd/etcd-key.pem \
  endpoint health

echo "✅ etcd installed and running"