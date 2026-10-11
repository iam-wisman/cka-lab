# Lab 06: RBAC with CSR-issued users, groups, aggregation and scoped ServiceAccounts

**Domain:** Cluster Architecture, Installation & Configuration (25%)
**Curriculum:** Manage role based access control (RBAC)
**Suggested time:** 60 minutes · **Start with:** `lab start 06` · **Work in:** `/home/student/rbac/` on `jump`

## Context

Kubernetes has no user objects. A "user" is whatever name and groups an
authenticator vouches for: here, the CN and O fields of a client certificate
signed by the cluster CA. You'll issue one through the CertificateSigningRequest
API, then give users, groups and a ServiceAccount exactly the access they need,
**and nothing more**.

`lab start 06` creates the namespaces `dev`, `staging` and `ci`, a Deployment
in `dev` and one in `staging`, and a Secret `dev/db-credentials`.

## Tasks

### 1. A developer: jane

1. Create a private key `~/rbac/jane.key` and a certificate request for user
   **`jane`** in group **`developers`**.
2. Submit it as a CertificateSigningRequest named **`jane`** for the API
   server client signer, valid for **7 days**, approve it, and save the
   issued certificate to `~/rbac/jane.crt`.
3. Build **`~/rbac/jane.kubeconfig`**:
   - cluster `cka-lab` at `https://k8s-api.cka.lab:6443`, the CA embedded
   - user `jane` with the certificate and key **embedded** (the file must work
     when copied to another machine)
   - context `jane@cka-lab`, default namespace **`dev`**, set as current

### 2. What developers may do in `dev`

Create a Role **`developer`** in `dev` and bind it, with a RoleBinding named
**`developer`**, to the **group** `developers` (not to jane personally).
Members of `developers` must be able to, in `dev` only:

- fully manage (get, list, watch, create, update, patch, delete) Deployments,
  Services and ConfigMaps
- get, list, watch and delete Pods, and read Pod logs
- get, list and watch ReplicaSets

They must **not** be able to read Secrets or `exec` into Pods, in `dev` or anywhere else.

### 3. Auditors, by aggregation

Members of the group **`auditors`** need read-only (get, list, watch) access,
cluster-wide, to Nodes, Namespaces, PersistentVolumes and StorageClasses, and
it must be **extensible without editing the role**:

1. ClusterRole **`cka-audit`** has **no rules of its own**. It aggregates every
   ClusterRole labelled `rbac.cka.lab/aggregate-to-audit: "true"`.
2. ClusterRole **`audit-nodes`** (nodes, namespaces) and ClusterRole
   **`audit-storage`** (persistentvolumes, storageclasses) carry that label.
3. ClusterRoleBinding **`auditors`** binds `cka-audit` to the group `auditors`.

Auditors can't read Pods, Secrets or anything else.

### 4. A CI ServiceAccount

1. ServiceAccount **`deployer`** in namespace **`ci`**. Pods using it must
   **not** get its token mounted automatically.
2. It may, **in `staging` only**: get, list, create, update and patch
   Deployments, and scale them through the `scale` subresource. Nothing else:
   no deletes, no Secrets, nothing in `dev` or `ci`. Use a Role and RoleBinding
   named **`deployer`** in `staging`.
3. Write a token for it, valid for exactly **2 hours**, to `~/rbac/deployer.token`.

## Grading

```
lab check 06
```

The grader tests effective permissions with impersonation
(`kubectl auth can-i --as ...`) and uses your `jane.kubeconfig` for real requests.

## Notes

- Verify as you go: `kubectl auth can-i --list --as jane --as-group developers -n dev`.
- Look at what `pods/log` and `deployments/scale` are, and how a Role refers to them.
- The CSR expiry is a field in the CSR spec; you don't need a custom CA.
- `kubectl auth whoami --kubeconfig ~/rbac/jane.kubeconfig` shows who the API
  server thinks you are.
