#!/bin/bash

set -euxo pipefail

CERTS="/vagrant/certs/generated"
CONFIGS="/vagrant/kubeconfigs/generated"

# 1. Create directories
mkdir -p /etc/kubernetes/config /etc/kubernetes/pki

# 2. Copy certs
cp ${CERTS}/ca.pem                  /etc/kubernetes/pki/
cp ${CERTS}/ca-key.pem              /etc/kubernetes/pki/
cp ${CERTS}/kubernetes.pem          /etc/kubernetes/pki/
cp ${CERTS}/kubernetes-key.pem      /etc/kubernetes/pki/
cp ${CERTS}/service-account.pem     /etc/kubernetes/pki/
cp ${CERTS}/service-account-key.pem /etc/kubernetes/pki/

# 3. Copy kubeconfigs
cp ${CONFIGS}/controller-manager.kubeconfig /etc/kubernetes/config/
cp ${CONFIGS}/scheduler.kubeconfig          /etc/kubernetes/config/

echo "✅ Control plane directories and certs ready"