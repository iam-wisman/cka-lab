# Lab 10: CRDs and operators, with cert-manager PKI and a CRD of your own

**Domain:** Cluster Architecture, Installation & Configuration (25%)
**Curriculum:** Understand CRDs, install and configure operators
**Suggested time:** 75 minutes

## Context

An operator is a controller that watches custom resources and does the work
they describe. You'll install a real one, **cert-manager**, and build a small
PKI with it that labs 22 and 23 reuse for TLS. Then you'll write a
CustomResourceDefinition yourself, with validation good enough that bad
objects never reach etcd.

## Part A: cert-manager

1. Install the **cert-manager** Helm chart **v1.21.2** (repository
   `https://charts.jetstack.io`) as release **`cert-manager`** in namespace
   **`cert-manager`**. The chart must install the CRDs itself, and they must
   **not** be deleted if the release is ever uninstalled.

2. Build a two-level PKI:

   | Object | Kind | Spec |
   |---|---|---|
   | `selfsigned-bootstrap` | ClusterIssuer | self-signed |
   | `cka-root-ca` | Certificate in `cert-manager` | a **CA** certificate, common name `CKA Lab Root CA`, ECDSA P-256 key, valid **10 years**, issued by `selfsigned-bootstrap`, stored in Secret `cka-root-ca` |
   | `cka-ca` | ClusterIssuer | signs with the CA in Secret `cka-root-ca` |

3. Issue Certificate **`app-tls`** in namespace **`apps`** (create it if
   needed) from **`cka-ca`**: DNS names `app.cka.lab` and `www.app.cka.lab`,
   valid **30 days**, renewed **10 days** before expiry, stored in Secret `app-tls`.

4. Everything `Ready=True`. The certificate in `apps/app-tls` must chain to
   `CKA Lab Root CA`.

5. Write the names of all CRDs cert-manager installed, sorted, one per line,
   to `~/answers/10-cert-manager-crds.txt`.

## Part B: your own CRD

The platform team wants to declare backups as Kubernetes objects. Create a
CRD so this works:

```yaml
apiVersion: ops.cka.lab/v1
kind: Backup
metadata: {name: nightly, namespace: ops}
spec:
  schedule: "0 2 * * *"
  target: ledger
```

Requirements:

1. Group `ops.cka.lab`, version `v1` (served and stored), kind `Backup`,
   plural `backups`, short name **`bk`**, namespaced.
2. Validation in the schema:
   - `spec.schedule` (string, a 5-field cron expression) and `spec.target`
     (string, at least 1 character) are **required**
   - `spec.retentionDays` is an integer from **1 to 30**, **defaulting to 7**
   - `status.phase` may only be `Pending`, `Succeeded` or `Failed`
3. `status` is a **subresource**: a normal update can't change it.
4. `kubectl get bk` shows the columns **SCHEDULE**, **TARGET**, **RETENTION**,
   **PHASE** and **AGE**.
5. Create the namespace `ops` and the `nightly` Backup above.

## Grading

```
lab check 10
```

The grader submits invalid Backups (server-side dry run) and expects the API
server to reject them.

## Notes

- cert-manager CA issuers: the CA's Secret must be in the **cluster resource
  namespace** (`cert-manager` by default) for a ClusterIssuer to find it.
- `kubectl explain` works on your own CRD once its schema is published.
- Write `x-kubernetes-*` and `default:` carefully: defaults only apply
  inside a structural schema.

## Cleaning up

After `lab check` passes:

```bash
kubectl delete namespace ops
kubectl delete crd backups.ops.cka.lab          # deleting a CRD deletes every object of that kind
kubectl -n apps delete certificate app-tls
kubectl -n apps delete secret app-tls
rm -f ~/answers/10-cert-manager-crds.txt
```

**Keep:** cert-manager, ClusterIssuers `selfsigned-bootstrap` and `cka-ca`, and Certificate/Secret `cert-manager/cka-root-ca`: labs 22 and 23 and the mock exams issue certificates from them.

## Restarting this lab

Part B: run the cleanup above, and you can redo it.

Part A (cert-manager) can't be torn down cleanly once labs 22 and 23 depend
on it. Uninstalling it and deleting its CRDs removes **every** Certificate and
Issuer in the cluster. Only do it before lab 22, or use a snapshot:

```bash
kubectl delete clusterissuer cka-ca selfsigned-bootstrap
kubectl -n cert-manager delete certificate cka-root-ca && kubectl -n cert-manager delete secret cka-root-ca
helm uninstall cert-manager -n cert-manager
kubectl delete crd -l app.kubernetes.io/instance=cert-manager      # CRDs are kept on uninstall
```
