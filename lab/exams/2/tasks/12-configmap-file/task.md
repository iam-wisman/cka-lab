## Task 12 (5 %) · Workloads & Scheduling

### Configuration as a file

Create ConfigMap **`app-conf`** in namespace `e2-t12` with key `app.conf` and
content `mode=strict`. Change Deployment `app` so the file appears at
**`/etc/app/app.conf`** in its container. The Deployment must roll out
successfully.
