## Task 8 (6 %) · Cluster Architecture

### Apply a Kustomize overlay

`/home/student/exam1/t8/base` contains a Kustomize base. Create an overlay in
`/home/student/exam1/t8/staging` that deploys it to namespace **`e1-t8`**
(the overlay creates the namespace), with **2 replicas**, the name prefix
**`stg-`** and the label **`env: staging`** on all resources. Apply it.
