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

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Using RBAC authorization (incl. aggregated ClusterRoles)](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Certificate signing requests: normal users](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/#normal-user)
- [Organizing cluster access using kubeconfig files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)
- [Service accounts](https://kubernetes.io/docs/concepts/security/service-accounts/)
- [kubectl create token](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_token/)
- [Authorization: checking API access (auth can-i)](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#checking-api-access)

## Cleaning up

After `lab check` passes, run **`lab cleanup 06`**. It shows the commands below and asks before running them. Or run them by hand:

```bash
kubectl delete namespace dev staging ci          # removes the Roles, RoleBindings, SA, Deployments, Secret
kubectl delete clusterrolebinding auditors
kubectl delete clusterrole cka-audit audit-nodes audit-storage
kubectl delete csr jane --ignore-not-found
rm -rf ~/rbac
```

## Restarting this lab

Run the cleanup above, then:

```bash
lab start 06
```

This recreates namespaces `dev`, `staging` and `ci` with their starting
objects (the Deployments and the `db-credentials` Secret).
