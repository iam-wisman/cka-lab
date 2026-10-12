## Task 5 (7 %) · Cluster Architecture

### A read-only reporter

Create ServiceAccount `reporter` in namespace `e1-t5`. Using **one** ClusterRole
named `pod-reader-e1` and RoleBindings, allow it to list and get Pods and read
Pod logs in namespaces `e1-t5` and `e1-apps`, **and nowhere else**.
