# Lab 09: Helm and Kustomize

**Domain:** Cluster Architecture, Installation & Configuration (25%) · Troubleshooting (30%)
**Curriculum:** Use Helm and Kustomize to install cluster components ·
Monitor cluster and application resource usage
**Suggested time:** 75 minutes · **Start with:** `lab start 09`

## Part A: metrics-server, the secure way

`kubectl top` and every HPA (lab 14) need **metrics-server**. Most tutorials
install it with `--kubelet-insecure-tls`. You won't: your kubelets have serving
certificates signed by the cluster CA (labs 03/05/07), so metrics-server can
verify them.

1. Install the **metrics-server** Helm chart **version 3.14.0** from the
   kubernetes-sigs chart repository as release **`metrics-server`** in
   **`kube-system`**, from a values file **`~/helm/metrics-server.yaml`**:
   - **2 replicas**, never both on the same node
   - a PodDisruptionBudget (`minAvailable: 1`) from the chart
   - **no** `--kubelet-insecure-tls`, and no other TLS-weakening argument
2. `kubectl top nodes` must show all five nodes, and `kubectl top pods -A`
   must work.

## Part B: a production overlay with Kustomize

`lab start 09` wrote a base to `~/kustomize/base` (a `shop` Deployment and
Service). Create the overlay **`~/kustomize/overlays/prod`** and apply it with
`kubectl apply -k`. The rendered result must be:

| Requirement | Detail |
|---|---|
| Namespace | everything in **`prod`**, and the overlay creates the namespace itself |
| Names | prefixed **`prod-`** |
| Label `env: prod` | on every resource **and** on the Pod template, but **not added to any selector** |
| Replicas | **3** |
| Image | `nginx` pinned to tag **`1.27.3-alpine`** (change the tag, not the image name) |
| Config | a generated ConfigMap **`shop-config`** with `MODE=production`, **with** its content-hash suffix, injected into the container with `envFrom` |
| Resources | container requests `cpu: 100m`, `memory: 64Mi`, added by a **patch** (the base is not edited) |

Don't modify anything in `~/kustomize/base`.

## Part C: Helm release lifecycle

1. Add the **podinfo** chart repository (`https://stefanprodan.github.io/podinfo`)
   and install chart **`podinfo` version 6.14.1** as release **`web`** in a
   new namespace **`apps`**, with **2 replicas**.
2. Upgrade the release (same chart version) to **3 replicas** and the UI
   message **`hello cka`**.
3. Roll the release back to **revision 1**.
4. Write the release's current revision number (just the number) to
   `~/answers/09-helm-revision.txt`.

## Grading

```
lab check 09
```

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Using Helm](https://helm.sh/docs/intro/using_helm/)
- [helm rollback](https://helm.sh/docs/helm/helm_rollback/)
- [Declarative management with Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
- [Kustomize: labels](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/labels/)
- [Resource metrics pipeline (metrics-server)](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
- [metrics-server](https://github.com/kubernetes-sigs/metrics-server)

## Cleaning up

After `lab check` passes, run **`lab cleanup 09`**. It shows the commands below and asks before running them. Or run them by hand:

```bash
kubectl delete -k ~/kustomize/overlays/prod      # also deletes namespace prod (the overlay owns it)
helm uninstall web -n apps
rm -rf ~/kustomize ~/answers/09-helm-revision.txt
```

Leave namespace `apps` itself: lab 10 issues a certificate into it.

**Keep:** The `metrics-server` release and `~/helm/metrics-server.yaml`: labs 14 and 31 and the mock exams need metrics.

## Restarting this lab

Run the cleanup above, then also remove metrics-server if you want to redo part A:

```bash
helm uninstall metrics-server -n kube-system
lab start 09                # rewrites the Kustomize base in ~/kustomize/base
```
