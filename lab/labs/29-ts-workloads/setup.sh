#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
kc delete namespace ts-apps --ignore-not-found --wait=true >/dev/null
kc apply -f - >/dev/null <<'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: ts-apps}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: ts-apps}
spec:
  replicas: 2
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec: {containers: [{name: web, image: nginx:1.27-alpinee}]}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: worker-config, namespace: ts-apps, labels: {owner: platform-team}}
data: {QUEUE: "amqp://queue.ts-apps:5672", WORKERS: "4"}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: worker, namespace: ts-apps}
spec:
  replicas: 1
  selector: {matchLabels: {app: worker}}
  template:
    metadata: {labels: {app: worker}}
    spec:
      containers:
        - name: worker
          image: busybox:1.37
          command: [sh, -c, 'echo "consuming $QUEUE_URL with $WORKERS workers"; sleep infinity']
          env:
            - name: QUEUE_URL
              valueFrom: {configMapKeyRef: {name: worker-config, key: QUEUE_URL}}
            - name: WORKERS
              valueFrom: {configMapKeyRef: {name: worker-config, key: WORKERS}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: cache, namespace: ts-apps}
spec:
  replicas: 1
  selector: {matchLabels: {app: cache}}
  template:
    metadata: {labels: {app: cache}}
    spec:
      nodeSelector: {disktype: nvme}
      containers: [{name: cache, image: redis:7-alpine}]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: db-data, namespace: ts-apps}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: fast-ssd
  resources: {requests: {storage: 1Gi}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: db, namespace: ts-apps}
spec:
  replicas: 1
  selector: {matchLabels: {app: db}}
  template:
    metadata: {labels: {app: db}}
    spec:
      containers:
        - name: db
          image: busybox:1.37
          command: [sh, -c, 'echo started > /var/lib/db/state; sleep infinity']
          volumeMounts: [{name: data, mountPath: /var/lib/db}]
      volumes: [{name: data, persistentVolumeClaim: {claimName: db-data}}]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: batch, namespace: ts-apps}
spec:
  replicas: 1
  selector: {matchLabels: {app: batch}}
  template:
    metadata: {labels: {app: batch}}
    spec:
      containers:
        - name: batch
          image: python:3.13-alpine
          command: [python3, -c, "import time; buf = bytearray(60 * 1024 * 1024); print('loaded 60MiB dataset', flush=True); time.sleep(10**9)"]
          resources:
            requests: {memory: 16Mi}
            limits: {memory: 32Mi}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: api, namespace: ts-apps}
spec:
  replicas: 2
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers:
        - name: api
          image: hashicorp/http-echo:1.0
          args: ["-listen=:8080", "-text=api ok"]
          ports: [{containerPort: 8080, name: http}]
          readinessProbe: {httpGet: {path: /, port: 8081}, periodSeconds: 3}
---
apiVersion: v1
kind: Service
metadata: {name: api, namespace: ts-apps}
spec: {selector: {app: api}, ports: [{port: 80, targetPort: http}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: crasher, namespace: ts-apps}
spec:
  replicas: 1
  selector: {matchLabels: {app: crasher}}
  template:
    metadata: {labels: {app: crasher}}
    spec:
      containers: [{name: crasher, image: busybox:1.37, command: [slep, "3600"]}]
YAML
kc -n ts-apps get cm worker-config -o jsonpath='{.metadata.resourceVersion}' >"$LAB_STATE/lab29-cm-rv"
echo "Namespace ts-apps is full of problems."
