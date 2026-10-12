# Lab 01: Prepare five bare Ubuntu servers for kubeadm

**Domain:** Cluster Architecture, Installation & Configuration (25%)
**Curriculum:** Prepare underlying infrastructure for installing a Kubernetes cluster ·
Understand extension interfaces (CRI)
**Suggested time:** 75 minutes · **Work from:** `jump` (`ssh <node>`, `sudo` is passwordless)

## Context

`cp1`, `cp2`, `cp3`, `worker1` and `worker2` are freshly installed Ubuntu 24.04
servers. Nothing for Kubernetes has been done to them, and like most real
installs they boot with swap enabled. Over the next labs you will turn them into
a highly available v1.34 cluster and later upgrade it to v1.35.

Everything you do here must **survive a reboot**. The grader reboots nothing,
but it checks the persistent configuration, not just the running state.

Leave `nfs` alone; it is not a Kubernetes node.

## Tasks

Apply all of the following to **all five** Kubernetes nodes.

1. **Swap.** The kubelet must be able to start with its default `failSwapOn`
   behaviour. Swap must be off now and must stay off after a reboot.

2. **Kernel modules.** `overlay` and `br_netfilter` must be loaded now and
   loaded automatically at boot, from a file under `/etc/modules-load.d/`.

3. **Kernel parameters.** Bridged IPv4 and IPv6 traffic must traverse
   iptables, and IPv4 forwarding must be on. Persist the settings in a file
   under `/etc/sysctl.d/`.

4. **Container runtime.** Install **containerd 2.x** from Docker's apt
   repository (package `containerd.io`). Then:
   - generate a full default configuration at `/etc/containerd/config.toml`
     (the package ships one that disables the CRI plugin)
   - make runc use the **systemd cgroup driver**
   - pin the sandbox (pause) image to **exactly** the one kubeadm v1.34.12
     expects. Find out which one that is; don't guess.
   - containerd must be enabled and running

5. **crictl.** `sudo crictl ps` must work with no flags and no warnings about
   a default endpoint: configure crictl to use containerd's socket for both the
   runtime and image endpoints.

6. **Kubernetes packages.** Install `kubeadm`, `kubelet` and `kubectl`
   **v1.34.12** from the community repository `pkgs.k8s.io` (the v1.34 channel).
   - pin them so `apt upgrade` cannot move them
   - the kubelet service must be enabled (it will crash-loop until lab 03; that's expected)

7. **Jump host tooling.** On `jump`, as `student`:
   - install `kubectl` v1.34.12 the same way (pinned)
   - kubectl bash completion must work for both `kubectl` and an alias `k`,
     in every new login shell

## Grading

```
lab check 01
```

The grader looks at each node over SSH: package versions and holds, the
effective containerd configuration (`containerd config dump`), live and
persisted kernel settings, `/proc/swaps` and `/etc/fstab`.

## Notes

- The exam gives you a cluster that already exists. Building one from parts is
  how you learn what each piece does, and that is what the troubleshooting
  domain (30%) tests.
- containerd 2 uses config version 3. Plugin names changed from 1.x
  (`io.containerd.grpc.v1.cri` became `io.containerd.cri.v1.runtime` and
  `io.containerd.cri.v1.images`), so most older blog posts are wrong now.
- Five nodes: consider doing one by hand, then scripting the rest.

## Cleaning up

`lab cleanup 01` has nothing to remove here.

Nothing to remove: what you built here **is** the cluster every later lab
uses. Take a snapshot instead so you can come back to this point:

```bash
lab snapshot after-01
```

## Restarting this lab

This lab changes the nodes themselves, so the only clean restart is a
snapshot. Take one **before** you start:

```bash
lab snapshot before-01
# ... attempt the lab ...
lab reset before-01        # all VMs roll back; reconnect to jump after ~1 minute
```

If you didn't take one, `lab reset base` returns all nodes to bare Ubuntu (the `lab` command stays installed).
