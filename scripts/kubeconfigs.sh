#!/bin/bash

set -euxo pipefail

if [ -f /vagrant/kubeconfigs/generated/admin.kubeconfig ]; then
  echo "✅ kubeconfigs already generated, skipping"
  exit 0
fi

CERTS="/vagrant/certs/generated"
OUT="/vagrant/kubeconfigs/generated"
mkdir -p $OUT

API_SERVER="https://${CONTROLLER_IP}:6443"

# Worker kubeconfigs
for i in $(seq 1 $NUM_WORKERS); do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=$CERTS/ca.pem \
    --embed-certs=true \
    --server=$API_SERVER \
    --kubeconfig=$OUT/worker-${i}.kubeconfig

  kubectl config set-credentials system:node:worker-${i} \
    --client-certificate=$CERTS/worker-${i}.pem \
    --client-key=$CERTS/worker-${i}-key.pem \
    --embed-certs=true \
    --kubeconfig=$OUT/worker-${i}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:worker-${i} \
    --kubeconfig=$OUT/worker-${i}.kubeconfig

  kubectl config use-context default \
    --kubeconfig=$OUT/worker-${i}.kubeconfig
done

# Controller Manager
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=$CERTS/ca.pem \
  --embed-certs=true \
  --server=$API_SERVER \
  --kubeconfig=$OUT/controller-manager.kubeconfig

kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=$CERTS/controller-manager.pem \
  --client-key=$CERTS/controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=$OUT/controller-manager.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-controller-manager \
  --kubeconfig=$OUT/controller-manager.kubeconfig

kubectl config use-context default \
  --kubeconfig=$OUT/controller-manager.kubeconfig

# Scheduler
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=$CERTS/ca.pem \
  --embed-certs=true \
  --server=$API_SERVER \
  --kubeconfig=$OUT/scheduler.kubeconfig

kubectl config set-credentials system:kube-scheduler \
  --client-certificate=$CERTS/scheduler.pem \
  --client-key=$CERTS/scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=$OUT/scheduler.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=system:kube-scheduler \
  --kubeconfig=$OUT/scheduler.kubeconfig

kubectl config use-context default \
  --kubeconfig=$OUT/scheduler.kubeconfig

# Admin
kubectl config set-cluster kubernetes-the-hard-way \
  --certificate-authority=$CERTS/ca.pem \
  --embed-certs=true \
  --server=$API_SERVER \
  --kubeconfig=$OUT/admin.kubeconfig

kubectl config set-credentials admin \
  --client-certificate=$CERTS/admin.pem \
  --client-key=$CERTS/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=$OUT/admin.kubeconfig

kubectl config set-context default \
  --cluster=kubernetes-the-hard-way \
  --user=admin \
  --kubeconfig=$OUT/admin.kubeconfig

kubectl config use-context default \
  --kubeconfig=$OUT/admin.kubeconfig

echo "All kubeconfigs generated successfully"