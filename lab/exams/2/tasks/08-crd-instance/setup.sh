#!/bin/bash
source "$LAB_HOME/lib/common.sh"
set -euo pipefail
grader_kubeconfig || die "the API server must be reachable"
mkdir -p "$HOME/exam2" "$LAB_STATE"
kc delete ns e2-t8 --ignore-not-found --wait=true >/dev/null; kc create ns e2-t8 >/dev/null
kc delete crd databaseclaims.data.cka.lab --ignore-not-found >/dev/null
cat >"$HOME/exam2/dbclaim-crd.yaml" <<'Y'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata: {name: databaseclaims.data.cka.lab}
spec:
  group: data.cka.lab
  scope: Namespaced
  names: {kind: DatabaseClaim, plural: databaseclaims, shortNames: [dbc]}
  versions:
    - name: v1alpha1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: [engine, storageSize]
              properties:
                engine: {type: string, enum: [postgres, mysql]}
                storageSize: {type: string, pattern: '^[0-9]+Gi$'}
                replicaCount: {type: integer, minimum: 1, maximum: 5}
Y
