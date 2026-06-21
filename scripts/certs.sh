#!/bin/bash

set -euxo pipefail

if [ -f /vagrant/certs/generated/ca.pem ]; then
  echo "✅ certs already generated, skipping"
  exit 0
fi

CERTS_DIR="/vagrant/certs/generated"
mkdir -p $CERTS_DIR
cd $CERTS_DIR

# Derive kubernetes service IP (first IP in service CIDR e.g. 10.32.0.0/24 -> 10.32.0.1)
K8S_SERVICE_IP=$(echo $SERVICE_CIDR | awk -F'[./]' '{print $1"."$2"."$3".1"}')

# 1. CA
cfssl gencert -initca /vagrant/certs/ca-csr.json | cfssljson -bare ca

# 2. Admin
cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=/vagrant/certs/ca-config.json \
  -profile=kubernetes \
  /vagrant/certs/admin-csr.json | cfssljson -bare admin


# Parse worker IP base from WORKER_IP_START
IP_NW=$(echo $WORKER_IP_START | grep -oP '^\d+\.\d+\.\d+\.')
IP_START=$(echo $WORKER_IP_START | grep -oP '\d+$')

# 3. Workers (one cert per worker, CN must match node name for kubelet)
for i in $(seq 1 $NUM_WORKERS); do
  WORKER_IP="${IP_NW}$((IP_START + i - 1))"
  cat > worker-${i}-csr.json <<EOF
{
  "CN": "system:node:worker-${i}",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [{ "O": "system:nodes" }]
}
EOF
  cfssl gencert \
    -ca=ca.pem -ca-key=ca-key.pem \
    -config=/vagrant/certs/ca-config.json \
    -profile=kubernetes \
    -hostname=worker-${i},${WORKER_IP} \
    worker-${i}-csr.json | cfssljson -bare worker-${i}
done

# 4. Controller Manager
cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=/vagrant/certs/ca-config.json \
  -profile=kubernetes \
  /vagrant/certs/controller-manager-csr.json | cfssljson -bare controller-manager

# 5. Scheduler
cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=/vagrant/certs/ca-config.json \
  -profile=kubernetes \
  /vagrant/certs/scheduler-csr.json | cfssljson -bare scheduler

# 6. API Server (needs all SANs it can be reached by)
cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=/vagrant/certs/ca-config.json \
  -profile=kubernetes \
  -hostname=${K8S_SERVICE_IP},${CONTROLLER_IP},127.0.0.1,controller-1,kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster.local \
  /vagrant/certs/kubernetes-csr.json | cfssljson -bare kubernetes

# 7. etcd
cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=/vagrant/certs/ca-config.json \
  -profile=kubernetes \
  -hostname=127.0.0.1,${CONTROLLER_IP},controller-1 \
  /vagrant/certs/etcd-csr.json | cfssljson -bare etcd

# 8. Service Account key pair
cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=/vagrant/certs/ca-config.json \
  -profile=kubernetes \
  /vagrant/certs/service-account-csr.json | cfssljson -bare service-account  

# 9. kube-proxy
cfssl gencert \
  -ca=ca.pem -ca-key=ca-key.pem \
  -config=/vagrant/certs/ca-config.json \
  -profile=kubernetes \
  /vagrant/certs/kube-proxy-csr.json | cfssljson -bare kube-proxy

echo "All certificates generated successfully"