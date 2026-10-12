## Task 16 (5 %) · Storage

### A StorageClass for retained data

Create StorageClass **`exam-retain`**, identical in provisioner and
parameters to `nfs-csi`, but that **keeps** volumes after their claims are
deleted and **waits for a consuming pod** before binding. It must **not** be
a default class, and `nfs-csi` must stay the only default.
