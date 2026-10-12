#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"

need_cluster
jqk() { kcq "${@:2}" -o json | jq -e "$1" >/dev/null; }   # jqk <jq-test> <kubectl get args...>

section "A: metrics-server"
ms=$(helm_release kube-system metrics-server)
check_eq "release metrics-server: chart metrics-server 3.14.0" "metrics-server 3.14.0" \
  jq -r '"\(.chart.metadata.name) \(.chart.metadata.version)"' <<<"${ms:-{\}}"
check "installed from ~/helm/metrics-server.yaml alone" release_values_match kube-system metrics-server "$HOME/helm/metrics-server.yaml"
check_eq "2 replicas available" "2 2" kcq -n kube-system get deploy metrics-server -o 'jsonpath={.spec.replicas} {.status.availableReplicas}'
check "replicas on different nodes" bash -c \
  "n=\$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system get pod -l app.kubernetes.io/name=metrics-server -o jsonpath='{.items[*].spec.nodeName}'); [[ \$(tr ' ' '\n' <<<\"\$n\" | sort -u | wc -l) == 2 ]]"
check "anti-affinity keeps them apart (required, by hostname)" jqk \
  '.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution | any(.[]; .topologyKey=="kubernetes.io/hostname")' \
  -n kube-system get deploy metrics-server
check_eq "PDB minAvailable 1" 1 kcq -n kube-system get pdb metrics-server -o 'jsonpath={.spec.minAvailable}'
check "no --kubelet-insecure-tls (or other TLS-skipping) argument" jqk \
  '[.spec.template.spec.containers[].args[]?] | all(test("insecure|tls-skip|skip-verify") | not)' -n kube-system get deploy metrics-server
check_eq "APIService v1beta1.metrics.k8s.io Available" True \
  kcq get apiservice v1beta1.metrics.k8s.io -o 'jsonpath={.status.conditions[?(@.type=="Available")].status}'
check_eq "kubectl top nodes shows all 5 nodes" 5 bash -c "$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG top nodes --no-headers 2>/dev/null | wc -l"
check "kubectl top pods -A works" kc top pods -A

section "B: Kustomize prod overlay"
check "base untouched (replicas 1, image nginx:1.27-alpine)" bash -c \
  "grep -q 'replicas: 1' ~/kustomize/base/deployment.yaml && grep -q 'image: nginx:1.27-alpine' ~/kustomize/base/deployment.yaml && ! grep -q 'resources' ~/kustomize/base/deployment.yaml"
check "overlay builds (kubectl kustomize)" kc kustomize "$HOME/kustomize/overlays/prod"
check "overlay creates namespace prod itself" bash -c \
  "$GRADER_KUBECTL kustomize $HOME/kustomize/overlays/prod 2>/dev/null | python3 -c 'import sys, yaml; sys.exit(0 if any(d and d.get(\"kind\")==\"Namespace\" and d[\"metadata\"][\"name\"]==\"prod\" for d in yaml.safe_load_all(sys.stdin)) else 1)'"
D=(-n prod get deploy prod-shop)
check "Deployment prod/prod-shop exists" kc "${D[@]}"
check "Service prod/prod-shop exists" kc -n prod get svc prod-shop
check_eq "replicas 3, all available" "3 3" kcq "${D[@]}" -o 'jsonpath={.spec.replicas} {.status.availableReplicas}'
check_eq "image nginx:1.27.3-alpine" nginx:1.27.3-alpine kcq "${D[@]}" -o 'jsonpath={.spec.template.spec.containers[0].image}'
check "env=prod on the Deployment, its Pod template, the Service and the Namespace" bash -c "
  k='$GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG'
  [[ \$(\$k -n prod get deploy prod-shop -o jsonpath='{.metadata.labels.env}/{.spec.template.metadata.labels.env}') == prod/prod ]] &&
  [[ \$(\$k -n prod get svc prod-shop -o jsonpath='{.metadata.labels.env}') == prod ]] &&
  [[ \$(\$k get ns prod -o jsonpath='{.metadata.labels.env}') == prod ]]"
check_eq "Deployment selector is still exactly {app: shop}" '{"app":"shop"}' kcq "${D[@]}" -o 'jsonpath={.spec.selector.matchLabels}'
check_eq "Service selector is still exactly {app: shop}" '{"app":"shop"}' kcq -n prod get svc prod-shop -o 'jsonpath={.spec.selector}'
cm=$(kcq "${D[@]}" -o 'jsonpath={.spec.template.spec.containers[0].envFrom[*].configMapRef.name}')
check_match "envFrom references generated prod-shop-config-<hash>" '^prod-shop-config-[a-z0-9]{10}$' echo "$cm"
check_eq "that ConfigMap has MODE=production" production kcq -n prod get cm "${cm:-none}" -o 'jsonpath={.data.MODE}'
check_eq "requests cpu 100m, memory 64Mi" "100m 64Mi" kcq "${D[@]}" -o 'jsonpath={.spec.template.spec.containers[0].resources.requests.cpu} {.spec.template.spec.containers[0].resources.requests.memory}'
check "requests added by a patch in the overlay" bash -c "grep -rqsE '^\s*patches:|^\s*patchesStrategicMerge:' ~/kustomize/overlays/prod/kustomization.yaml"

section "C: Helm lifecycle (podinfo)"
web=$(helm_release apps web)
check_eq "release web: chart podinfo 6.14.1" "podinfo 6.14.1" jq -r '"\(.chart.metadata.name) \(.chart.metadata.version)"' <<<"${web:-{\}}"
check_eq "current revision is 3 (install, upgrade, rollback)" 3 jq -r '.version' <<<"${web:-{\}}"
check_eq "revision 3 is a rollback to 1" "Rollback to 1" jq -r '.info.description' <<<"${web:-{\}}"
check_eq "running with revision 1's values: 2 replicas" "2 2" kcq -n apps get deploy web-podinfo -o 'jsonpath={.spec.replicas} {.status.availableReplicas}'
check "revision 2 had 3 replicas and message 'hello cka'" bash -c "
  $GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n apps get secret sh.helm.release.v1.web.v2 -o jsonpath='{.data.release}' | base64 -d | base64 -d | gunzip |
  jq -e '.config.replicaCount == 3 and .config.ui.message == \"hello cka\"'"
check_eq "answers/09-helm-revision.txt says 3" 3 cat "$HOME/answers/09-helm-revision.txt"

finish
