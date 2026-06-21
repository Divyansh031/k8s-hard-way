#!/bin/bash

set -euxo pipefail

KUBECONFIG="/vagrant/kubeconfigs/generated/admin.kubeconfig"

if kubectl --kubeconfig=$KUBECONFIG get deployment coredns -n kube-system &>/dev/null; then
  echo "✅ CoreDNS already deployed, skipping"
  exit 0
fi

# 1. Create ServiceAccount, ClusterRole, ClusterRoleBinding
kubectl apply --kubeconfig=$KUBECONFIG -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:coredns
rules:
  - apiGroups: [""]
    resources: [endpoints, services, pods, namespaces]
    verbs: [list, watch]
  - apiGroups: [""]
    resources: [nodes]
    verbs: [get]
  - apiGroups: [discovery.k8s.io]
    resources: [endpointslices]
    verbs: [list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:coredns
subjects:
  - kind: ServiceAccount
    name: coredns
    namespace: kube-system
EOF

# 2. CoreDNS ConfigMap
kubectl apply --kubeconfig=$KUBECONFIG -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
          lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
          ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {
          max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
EOF

# 3. CoreDNS Deployment
kubectl apply --kubeconfig=$KUBECONFIG -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
    spec:
      serviceAccountName: coredns
      tolerations:
        - operator: Exists
      containers:
        - name: coredns
          image: coredns/coredns:1.12.0
          args: ["-conf", "/etc/coredns/Corefile"]
          ports:
            - containerPort: 53
              protocol: UDP
              name: dns
            - containerPort: 53
              protocol: TCP
              name: dns-tcp
            - containerPort: 9153
              protocol: TCP
              name: metrics
          volumeMounts:
            - name: config-volume
              mountPath: /etc/coredns
              readOnly: true
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 60
            timeoutSeconds: 5
          readinessProbe:
            httpGet:
              path: /ready
              port: 8181
            initialDelaySeconds: 10
            timeoutSeconds: 5
      volumes:
        - name: config-volume
          configMap:
            name: coredns
            items:
              - key: Corefile
                path: Corefile
EOF

# 4. CoreDNS Service (ClusterIP must match CLUSTER_DNS)
kubectl apply --kubeconfig=$KUBECONFIG -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
spec:
  clusterIP: ${CLUSTER_DNS}
  selector:
    k8s-app: kube-dns
  ports:
    - name: dns
      port: 53
      protocol: UDP
    - name: dns-tcp
      port: 53
      protocol: TCP
EOF

echo "✅ CoreDNS deployed"

# 5. Wait for it to be ready
echo "Waiting for CoreDNS to be ready..."
kubectl rollout status deployment/coredns -n kube-system \
  --kubeconfig=$KUBECONFIG --timeout=120s