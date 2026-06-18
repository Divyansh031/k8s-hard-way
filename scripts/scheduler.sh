#!/bin/bash

set -euxo pipefail

# 1. Download binary
wget -q --show-progress \
  "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/amd64/kube-scheduler"
chmod +x kube-scheduler
mv kube-scheduler /usr/local/bin/

# 2. Scheduler config
cat <<EOF > /etc/kubernetes/config/kube-scheduler.yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: /etc/kubernetes/config/scheduler.kubeconfig
leaderElection:
  leaderElect: true
EOF

# 3. Create systemd unit
cat <<EOF > /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://kubernetes.io/docs

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 4. Start
systemctl daemon-reload
systemctl enable kube-scheduler
systemctl start kube-scheduler

sleep 3
systemctl is-active kube-scheduler

echo "✅ kube-scheduler running"