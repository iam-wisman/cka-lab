### Deployment behind a Service, by port name

In namespace `{{NS}}`:

1. Deployment **`{{DEP}}`**: **{{REP}}** replicas of `httpd:2.4-alpine`, container
   port 80 **named `web`**.
2. ClusterIP Service **`{{SVC}}`** on port **{{PORT}}**, targeting the container
   port **by name**.

Every replica must be a ready endpoint of the Service.

**Time budget:** 2:00
