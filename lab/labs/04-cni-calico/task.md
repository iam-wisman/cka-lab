# Lab 04: Install Calico with Helm and the Tigera operator

**Domain:** Cluster Architecture, Installation & Configuration (25%)
**Curriculum:** Use Helm and Kustomize to install cluster components ·
Understand extension interfaces (CNI) · Understand connectivity between Pods
**Suggested time:** 45 minutes · **Work on:** `jump`

## Context

`cp1` is `NotReady` because no CNI plugin is installed: the kubelet reports
`NetworkPluginNotReady` and CoreDNS can't get a pod IP. Install **Calico**
using its Helm chart, which deploys the **Tigera operator**. The operator then
installs Calico itself from an `Installation` custom resource.

Calico must agree with the pod network you gave kubeadm in lab 03. If they
disagree, pods get IPs from the wrong range, and routing and NetworkPolicy
(lab 21) break in confusing ways.

## Tasks

1. **Helm.** Install the latest **Helm 3** release on `jump` for `student`.

2. **Values file.** Write the chart values to `/home/student/calico/values.yaml`
   and install from that file (no `--set`). The `Installation` must have
   exactly one IPv4 pool:

   | Field | Value |
   |---|---|
   | name | `default-ipv4-ippool` |
   | CIDR | the pod subnet from lab 03 |
   | encapsulation | VXLAN on all traffic (not only cross-subnet) |
   | outgoing NAT | enabled |
   | block size | `/24` per node |

   This is an overlay-only design: turn **BGP off**.

3. **Install.** Release name `calico`, namespace `tigera-operator`, chart
   `tigera-operator` **version v3.32.2** from the Calico chart repository.
   Follow the Helm instructions **for exactly that Calico version** (the
   procedure changed between releases), and install everything else it needs
   at the same version.

4. **Healthy.** Every component in `kubectl get tigerastatus` must be
   `AVAILABLE=True`, `cp1` must be `Ready`, and both CoreDNS pods must be
   `Running` with IPs from the pod subnet.

5. **Understand what got installed (CNI).** On `cp1`, find which CNI
   configuration file the container runtime loads and where the CNI plugin
   binaries are. Write two lines to `/home/student/answers/04-cni.txt` on
   `jump`:

   ```
   config=<absolute path of the CNI config file on cp1>
   bin_dir=<absolute path of the CNI binary directory on cp1>
   ```

## Grading

```
lab check 04
```

## Notes

- `helm show values` on the chart shows the `installation:` key: its
  contents become the `Installation` resource's `spec`.
- If you install with the wrong CIDR, changing the values afterwards is not
  enough: Calico doesn't change an existing IP pool's CIDR. Read the
  operator's docs on what can and can't be changed, then decide whether to
  uninstall cleanly or `lab reset`.
- containerd decides which CNI config to load. `containerd config dump` shows
  the directories it uses.

## References

Official documentation. Practise finding answers on kubernetes.io: it is the main resource the exam lets you open (the Linux Foundation candidate handbook has the current list).

- [Network plugins (CNI)](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
- [Cluster networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
- [Calico 3.32: install with Helm](https://docs.tigera.io/calico/3.32/getting-started/kubernetes/helm)
- [Installing Helm](https://helm.sh/docs/intro/install/)

## Cleaning up

After `lab check` passes, run **`lab cleanup 04`**. It shows the commands below and asks before running them. Or run them by hand:

Remove only the answer file:

```bash
rm -f ~/answers/04-cni.txt
```

**Keep:** Helm and the `calico` release: pods have no network without it.

## Restarting this lab

Uninstall Calico, including the CRDs you applied separately, then start over:

```bash
helm uninstall calico -n tigera-operator
kubectl delete installation default --ignore-not-found
helm template calico-crds projectcalico/crd.projectcalico.org.v1 --version v3.32.2 | kubectl delete -f - --ignore-not-found
kubectl delete namespace tigera-operator calico-system --ignore-not-found
for n in cp1 cp2 cp3 worker1 worker2; do ssh $n 'sudo rm -f /etc/cni/net.d/*calico*'; done
```

Pods lose networking until you reinstall. A snapshot (`lab snapshot before-04`) is the faster route.
