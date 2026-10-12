## Task 14 (5 %) · Workloads & Scheduling

### Use the reserved node

`worker2` has been reserved: it carries the taint `reserved=e1:NoSchedule`.
Create Pod **`batch`** in namespace `e1-t14` (`busybox:1.37`, `sleep 3600`) that
runs **on worker2 and only there**.
