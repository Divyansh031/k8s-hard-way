#!/bin/bash

set -euxo pipefail

KUBECONFIG="/vagrant/kubeconfigs/generated/admin.kubeconfig"

# Skip if already applied
if kubectl --kubeconfig=$KUBECONFIG get clusterrole system:kube-apiserver-to-kubelet &>/dev/null; then
  echo "✅ RBAC already configured, skipping"
  exit 0
fi

kubectl apply --kubeconfig=$KUBECONFIG -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:kube-apiserver-to-kubelet
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
rules:
  - apiGroups: [""]
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs: ["*"]
EOF

kubectl apply --kubeconfig=$KUBECONFIG -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF

echo "✅ RBAC configured"