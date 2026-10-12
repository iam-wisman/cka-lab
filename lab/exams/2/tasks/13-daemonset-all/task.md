## Task 13 (5 %) · Workloads & Scheduling

### An agent on every node

Create DaemonSet **`log-agent`** in namespace `e2-t13` (`busybox:1.37`,
`sleep infinity`) that runs on **every** node of the cluster, control planes
included.
