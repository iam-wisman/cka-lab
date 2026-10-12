# Lab 11: CRI, CNI and CSI from the node's point of view

**Domain:** Cluster Architecture, Installation & Configuration (25%) · Troubleshooting (30%)
**Curriculum:** Understand extension interfaces (CNI, CSI, CRI, etc.)
**Suggested time:** 50 minutes · **Start with:** `lab start 11`

## Context

Kubernetes doesn't run containers, wire networks or attach disks itself. The
kubelet asks a **CRI** runtime (containerd) for containers, the runtime calls
a **CNI** plugin (Calico) for pod networking, and **CSI** drivers provide
storage. When the API server is down, these interfaces and their tools are all
you have.

## Tasks

1. **Find the stranger.** `lab start 11` started a container on one of the
   workers **directly through containerd**, outside Kubernetes. `kubectl` can't
   see it, and it isn't a pod. Find it, and stop and remove it (container and
   task) without restarting containerd or the node.

2. **Registry mirror (CRI configuration).** On **worker2 only**, make
   containerd pull images for `docker.io` through the mirror
   **`https://mirror.gcr.io`**, falling back to Docker Hub
   (`https://registry-1.docker.io`). Use containerd's per-registry host
   configuration directory (not the deprecated `mirrors` config section).
   `sudo crictl pull docker.io/library/alpine:3.20` must work on worker2 afterwards.

3. **RuntimeClass.** Create a RuntimeClass **`runc-std`** that maps to
   containerd's `runc` handler, and a Pod **`rc-test`** in namespace
   `default` (image `busybox:1.37`, command `sleep 3600`) that uses it.

4. **Answer from the nodes.** Write `~/answers/11-interfaces.txt` with exactly
   these keys, one `key=value` per line, finding each answer yourself:

   ```
   apiserver_container_cp2=<container ID of the running kube-apiserver container on cp2, first 13 characters>
   apiserver_pod_sandbox_cp2=<pod sandbox ID of that container, first 13 characters>
   cni_ipam_plugin=<the IPAM plugin type in the CNI config containerd uses>
   cri_socket=<the CRI endpoint the kubelet on worker1 is configured with>
   csi_drivers=<names of all CSIDriver objects in the cluster, sorted, comma-separated, or none>
   ```

## Grading

```
lab check 11
```

## Notes

- `crictl` talks CRI, the same interface the kubelet uses, so it only sees what
  the kubelet would. containerd's own client is `ctr`; mind its **namespaces**
  (`ctr ns ls`).
- In containerd 2, registry hosts are configured as
  `<config_path>/<registry>/hosts.toml`. Find `config_path` in the effective
  config, then read the "Registry Configuration" document in the containerd repo.
- Where does the kubelet read its runtime endpoint from? Look at its config
  file, not just its command line.

## Cleaning up

After `lab check` passes:

```bash
kubectl delete pod rc-test
kubectl delete runtimeclass runc-std
rm -f ~/answers/11-interfaces.txt
```

The docker.io mirror on worker2 is harmless to keep. To remove it, delete
`/etc/containerd/certs.d/docker.io/` on worker2 and restart containerd.

## Restarting this lab

Run the cleanup above, undo the mirror on worker2, then plant the rogue container again:

```bash
ssh worker2 "sudo rm -rf /etc/containerd/certs.d/docker.io && sudo sed -i \"s#config_path = '/etc/containerd/certs.d'#config_path = ''#\" /etc/containerd/config.toml && sudo systemctl restart containerd"
lab start 11
```
