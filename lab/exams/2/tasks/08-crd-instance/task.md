## Task 8 (6 %) · Cluster Architecture

### Use a custom resource

Install the CRD in `/home/student/exam2/dbclaim-crd.yaml`. Then, in namespace
`e2-t8`, create a resource of that kind named **`orders-db`** with engine
`postgres`, size `20Gi` and 2 replicas. Use `kubectl explain` to find the field
names; the API server must accept it.
