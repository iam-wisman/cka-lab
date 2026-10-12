# Lab 03: Bootstrap the first control plane with a kubeadm config file

**Domain:** Cluster Architecture, Installation & Configuration (25%)
**Curriculum:** Create and manage Kubernetes clusters using kubeadm ·
Manage the lifecycle of Kubernetes clusters
**Suggested time:** 60 minutes · **Work on:** `cp1`, then `jump`

## Context

Initialise the cluster on `cp1`. Flags won't get you everything this cluster
needs: write a kubeadm **configuration file** containing four documents
(`InitConfiguration`, `ClusterConfiguration`, `KubeletConfiguration`,
`KubeProxyConfiguration`) and run `kubeadm init --config`. Keep the file at
`/root/kubeadm-config.yaml` on `cp1`; you'll need it again.

Later labs depend on the values below. Get them wrong and you'll be rebuilding
the cluster (`lab reset`).

## Tasks

1. **Cluster identity and networking** (`ClusterConfiguration`, API `kubeadm.k8s.io/v1beta4`):

   | Setting | Value |
   |---|---|
   | cluster name | `cka-lab` |
   | Kubernetes version | `v1.34.12` |
   | control-plane endpoint | `k8s-api.cka.lab:6443` |
   | pod network | `172.16.0.0/16` |
   | service network | `10.112.0.0/16` |
   | cluster DNS domain | `cka.local` (not `cluster.local`!) |

   The API server certificate must also be valid for `10.10.10.10`.

2. **This node** (`InitConfiguration`): advertise on `10.10.10.11:6443`, use
   containerd's CRI socket explicitly, and register the node as `cp1`.

3. **Upload the control-plane certificates** to the cluster during init, so
   lab 05 can join more control planes without copying files by hand.

4. **Kubelet** (`KubeletConfiguration`): systemd cgroup driver, and the
   kubelet must request a **serving certificate** from the cluster CA instead of
   using a self-signed one (later, metrics-server will verify it).

5. **kube-proxy** (`KubeProxyConfiguration`): run in **nftables** mode.

6. Don't install a CNI plugin yet (that's lab 04). `cp1` will be `NotReady`
   and CoreDNS `Pending`; that's expected.

7. **kubectl on jump.** As `student` on `jump`, `kubectl get nodes` must work
   through `k8s-api.cka.lab:6443` (the load balancer from lab 02, not
   `cp1`'s address) using cluster-admin credentials in `~/.kube/config`.

8. **Make `kubectl logs` work.** Because of item 4, the kubelet on `cp1` asks
   for a serving certificate, and nothing approves it automatically. Until it
   is approved, `kubectl logs` and `kubectl exec` against pods on `cp1` fail
   with a TLS error. Approve the right CertificateSigningRequest(s), and only
   those: don't approve anything that isn't a kubelet serving request for
   `cp1`.

## Grading

```
lab check 03
```

The grader reads the configuration kubeadm stored in the cluster (the
`kubeadm-config`, `kubelet-config` and `kube-proxy` ConfigMaps), the API server
certificate on `cp1`, and your `~/.kube/config` on `jump`.

## Notes

- `kubeadm config print init-defaults --component-configs KubeletConfiguration,KubeProxyConfiguration`
  prints a starting point with all four documents.
- `kubeadm init` has `--dry-run`, and `kubeadm reset -f` undoes a failed
  attempt (it leaves `/etc/cni/net.d` and iptables/nftables rules behind; read
  its output).
- Save the `kubeadm join` commands init prints. You'll regenerate them in lab
  05 anyway: the uploaded certificates expire after two hours.

## Cleaning up

After `lab check` passes:

Nothing to remove: what you built here **is** the cluster every later lab
uses. Take a snapshot instead so you can come back to this point:

```bash
lab snapshot after-03
```

**Keep:** `/root/kubeadm-config.yaml` on cp1, and `~/.kube/config` on jump.

## Restarting this lab

This lab changes the nodes themselves, so the only clean restart is a
snapshot. Take one **before** you start:

```bash
lab snapshot before-03
# ... attempt the lab ...
lab reset before-03        # all VMs roll back; reconnect to jump after ~1 minute
```

If you didn't take one, undo the init by hand on cp1, then delete the old credentials on jump:

```bash
ssh cp1 'sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d $HOME/.kube'
rm -f ~/.kube/config
```

`kubeadm reset` leaves nftables/iptables rules behind; reboot cp1 to clear them.
