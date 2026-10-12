# Lab 27: Troubleshoot NotReady nodes

**Domain:** Troubleshooting (30%)
**Curriculum:** Troubleshoot clusters and nodes · Troubleshoot cluster components
**Suggested time:** 45 minutes · **Start with:** `lab start 27`

## Situation

After an "unattended maintenance window", `worker1` and `worker2` are
`NotReady` (wait a minute after `lab start 27` for the node controller to
notice). Each has **more than one** problem.

## Tasks

1. Bring **both** nodes back to `Ready`.
2. Fix every root cause **persistently**: the nodes must come back healthy
   after a reboot without anyone touching them.
3. **Don't** reset, re-join or recreate the nodes (the grader checks the Node
   objects are the originals), and don't change anything on the control planes.

## Grading

```
lab check 27
```

## Notes

- `kubectl describe node` tells you *that* the kubelet stopped reporting. The
  node itself tells you *why*: `systemctl status`, `journalctl -u kubelet`,
  `crictl`.
- When the kubelet keeps exiting, its log shows the reason in the last lines
  before each restart.
- `kubeadm` is not the tool here. Think about files, services and the kernel.

## Cleaning up

After `lab check` passes:

Nothing to remove: the fixed nodes are the end state. Check you didn't leave
anything behind:

```bash
ssh worker2 'ls /swap2.img 2>/dev/null; grep swap /etc/fstab'      # no active swap entry
```

## Restarting this lab

```bash
lab start 27
```

This breaks worker1 and worker2 again, the same way, and re-records the
Node objects' identities for the grader.
