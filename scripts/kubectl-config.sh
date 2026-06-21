#!/bin/bash

set -euxo pipefail

# Set admin kubeconfig for vagrant user on controller
if grep -q "KUBECONFIG" /home/vagrant/.bashrc; then
  echo "✅ KUBECONFIG already set, skipping"
  exit 0
fi

echo 'export KUBECONFIG=/vagrant/kubeconfigs/generated/admin.kubeconfig' >> /home/vagrant/.bashrc

echo "✅ KUBECONFIG configured"