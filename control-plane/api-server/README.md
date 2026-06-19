# kube-apiserver

## What is it?

The API server is the **front door to the entire Kubernetes cluster**. Every single interaction with the cluster — whether from `kubectl`, the controller-manager, the scheduler, or a pod — goes through the API server. Nothing talks to etcd directly except the API server.

Think of it as the receptionist of a building. Every visitor (request) must check in here first, get verified, and then get routed to the right place.

---

## What does it do?

- Receives all REST API requests
- Authenticates the caller (is this a valid certificate?)
- Authorizes the request (is this caller allowed to do this?)
- Validates and admits the request (does this object make sense?)
- Reads/writes cluster state to etcd
- Notifies watchers (scheduler, controller-manager, kubelets) of changes

---

## How we set it up

### 1. Certificates copied to `/etc/kubernetes/pki/`

```
/etc/kubernetes/pki/
├── ca.pem                  # CA cert — used to verify all incoming client certs
├── ca-key.pem              # CA key — used to sign kubelet certs dynamically
├── kubernetes.pem          # API server's own TLS cert (presented to clients)
├── kubernetes-key.pem      # API server's own TLS key
├── service-account.pem     # Used to VERIFY service account tokens issued to pods
└── service-account-key.pem # Used to SIGN service account tokens (used by controller-manager)
```

### 2. Systemd unit at `/etc/systemd/system/kube-apiserver.service`

Key flags explained:

| Flag | What it does |
|---|---|
| `--advertise-address` | IP the API server advertises to the cluster (our controller IP) |
| `--authorization-mode=Node,RBAC` | Node authorizer for kubelets + RBAC for everything else |
| `--client-ca-file` | CA cert to verify incoming client certificates |
| `--etcd-servers` | Where to find etcd (localhost since it runs on the same node) |
| `--etcd-cafile/certfile/keyfile` | mTLS certs to talk to etcd securely |
| `--service-cluster-ip-range` | IP range for ClusterIP services (e.g. 10.32.0.0/24) |
| `--service-account-issuer` | Issuer URL embedded in service account JWT tokens |
| `--service-account-key-file` | Public key to verify pod service account tokens |
| `--service-account-signing-key-file` | Private key to sign pod service account tokens |
| `--tls-cert-file/key-file` | The API server's own TLS identity |

---

## Communication flow

```
kubectl / external client
        │
        │ HTTPS :6443 (TLS — server presents kubernetes.pem)
        ▼
  kube-apiserver
        │
        ├──► etcd :2379 (mTLS — presents etcd.pem, verifies with ca.pem)
        │      stores/reads all cluster state
        │
        ├──► kubelet :10250 (HTTPS)
        │      for kubectl logs, exec, port-forward
        │
        ├──► notifies kube-scheduler (watches for unscheduled pods)
        │
        └──► notifies kube-controller-manager (watches for desired vs actual state)
```

---

## Why the API server needs so many certs

The API server acts as both a **server** (presenting its cert to clients) and a **client** (presenting certs to etcd and kubelet). So it needs:

- Its own TLS identity (`kubernetes.pem`) — server role
- etcd client certs — client role when talking to etcd  
- CA cert — to verify everyone who talks to it
- Service account keys — to issue and verify pod tokens

---

## Verify it's working

```bash
# Check service status
sudo systemctl status kube-apiserver

# Check logs
sudo journalctl -u kube-apiserver -n 50 --no-pager

# Hit the version endpoint (requires certs since we enabled client-cert-auth)
sudo kubectl version --kubeconfig=/vagrant/kubeconfigs/generated/admin.kubeconfig
```

---

## Script

`scripts/api-server.sh` — downloads the binary, writes the systemd unit, and starts the service.

Env vars required:
- `CONTROLLER_IP` — the advertise address and part of the SAN list
- `KUBERNETES_VERSION` — which binary to download
- `SERVICE_CIDR` — the ClusterIP range