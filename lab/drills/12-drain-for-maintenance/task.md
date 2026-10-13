### Drain a worker past a PodDisruptionBudget

Take **`{{NODE}}`** out for maintenance: nothing new may be scheduled to it, and
every pod on it except DaemonSet pods must be gone. Deployment **`{{DEP}}`** in
`{{NS}}` must end with all its replicas ready on other nodes. Don't change or
delete its PodDisruptionBudget.

**Time budget:** 3:00
