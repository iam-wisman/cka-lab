## Task 11 (6 %) · Services & Networking

### Expose a Deployment on every node

Expose Deployment `web` in namespace `e1-t11` as a NodePort Service named
**`web`** on node port **30111**. The Service must target the container port by
its **name**. `curl http://worker1:30111` from `jump` must answer.
