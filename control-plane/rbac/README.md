# RBAC — Role Based Access Control

## What is it?

RBAC is Kubernetes' authorization system. It controls **who can do what to which resources**. After a request is authenticated (we know who you are), RBAC decides if you're actually allowed to do it.

We enabled it with `--authorization-mode=Node,RBAC` on the API server. This means two authorization modes run in order:

- **Node** — a special mode specifically for kubelets, letting them only access resources related to their own node
- **RBAC** — for everything else

---

## Core concepts

### Role vs ClusterRole

| | Role | ClusterRole |
|---|---|---|
| Scope | Single namespace | Entire cluster |
| Use for | app permissions | node access, cluster-wide APIs |

### RoleBinding vs ClusterRoleBinding

Binds a Role/ClusterRole to a **subject** (User, Group, or ServiceAccount).

```
ClusterRole (what's allowed)
      +
ClusterRoleBinding (who gets it)
      =
Subject can perform those actions
```

---

## What we configured

### The problem we're solving

The API server needs to talk to kubelets — for `kubectl logs`, `kubectl exec`, `kubectl port-forward`. But by default with RBAC enabled, the API server doesn't have permission to call the kubelet API.

The API server authenticates to kubelets using its `kubernetes.pem` cert, which has `CN=kubernetes`. So we need to grant the `kubernetes` user permission to hit kubelet endpoints.

### ClusterRole: `system:kube-apiserver-to-kubelet`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups: [""]
    resources:
      - nodes/proxy    # kubectl port-forward
      - nodes/stats    # metrics
      - nodes/log      # kubectl logs
      - nodes/spec     # node info
      - nodes/metrics  # prometheus scraping
    verbs: ["*"]
```

This ClusterRole says: whoever has this role can do anything to these node sub-resources.

### ClusterRoleBinding: `system:kube-apiserver`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
roleRef:
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - kind: User
    name: kubernetes          # matches CN in kubernetes.pem
    apiGroup: rbac.authorization.k8s.io
```

This binding says: the user `kubernetes` gets the `system:kube-apiserver-to-kubelet` role.

The `name: kubernetes` matches the `CN=kubernetes` field in `kubernetes.pem` — that's how Kubernetes knows who is making the request when the API server calls a kubelet.

---

## Full authorization flow

```
kubectl logs worker-1 some-pod
        │
        ▼
  kube-apiserver receives request
        │
        ├── Authentication: is the client cert valid? (yes — signed by our CA)
        │
        ├── Authorization (RBAC): is this user allowed?
        │     subject = "kubernetes" (from CN in kubernetes.pem)
        │     action  = GET nodes/log
        │     RBAC check: does "kubernetes" have a binding that allows this? YES ✅
        │
        └── Proxies request to kubelet :10250 on worker-1
              presenting kubernetes.pem as its identity
```

Without this RBAC setup, the API server would be denied by its own authorization layer when trying to proxy to kubelets — even though it's the API server itself making the call.

---

## Other RBAC that exists by default

When you enable RBAC, Kubernetes ships with a set of built-in ClusterRoles:

| ClusterRole | Purpose |
|---|---|
| `cluster-admin` | Full access to everything |
| `system:node` | What kubelets are allowed to do |
| `system:kube-scheduler` | What the scheduler is allowed to do |
| `system:kube-controller-manager` | What the controller-manager is allowed to do |
| `view` | Read-only access to most resources |
| `edit` | Read-write, no RBAC changes |
| `admin` | Full namespace access |

These are automatically created when RBAC is enabled — we only needed to add the api-server-to-kubelet one manually because that's a custom need for our setup.

---

## Verify it's configured

```bash
kubectl get clusterrole system:kube-apiserver-to-kubelet \
  --kubeconfig=/vagrant/kubeconfigs/generated/admin.kubeconfig

kubectl get clusterrolebinding system:kube-apiserver \
  --kubeconfig=/vagrant/kubeconfigs/generated/admin.kubeconfig

# See full details
kubectl describe clusterrolebinding system:kube-apiserver \
  --kubeconfig=/vagrant/kubeconfigs/generated/admin.kubeconfig
```

---

## Script

`scripts/rbac.sh` — applies the ClusterRole and ClusterRoleBinding using the admin kubeconfig. Idempotent — skips if the ClusterRole already exists.

No env vars required — uses the admin kubeconfig path directly.