# Kubestronaut roadmap

The goal: one platform that prepares for all five certifications a Kubestronaut
holds, **CKA, CKAD, CKS, KCNA and KCSA**, at a difficulty **above** the real
exams. Every track follows its official CNCF curriculum (`lab/tracks.json`;
`tools/check-versions.py` reports new curricula).

The console takes them in this order: **CKA → CKS → CKAD → KCNA → KCSA**. The
CKA builds the cluster everything else runs on; the CKS secures it (and needs a
passed CKA); the CKAD ships applications on it; the two multiple-choice exams
come last, when most of their content is revision.

Rules for all content:

- No hints. A task states the requirement and links the official docs, nothing
  more.
- Harder than the exam: multi-step tasks, faults to find first, traps the real
  exam also uses (contexts, namespaces, immutable fields), tighter clocks.
- Fresh values per attempt (`params`), so retakes test skill, not memory.
- Every grader is proven against a reference solution (private repo) before it
  ships.

## Status

| Track | Format | Curriculum | Status |
|---|---|---|---|
| CKA | hands-on | v1.35 | 31 labs, 2 mock exams, 12 speed drills |
| CKAD | hands-on | v1.37 | domains mapped; labs below are planned |
| CKS | hands-on | v1.34 | domains mapped; labs and cluster add-ons below are planned |
| KCNA | multiple choice | current | quiz engine done; seed bank of 34 questions |
| KCSA | multiple choice | current | quiz engine done; seed bank of 36 questions |

## CKAD (v1.37): planned labs

Runs on the same cluster as CKA, in `lab/tracks/ckad/`.

| # | Lab | Domain |
|---|---|---|
| 01 | Build, tag and push images with a Containerfile to a registry in the cluster; multi-stage; non-root | Design & Build |
| 02 | Pick the right workload: Deployment vs StatefulSet vs DaemonSet vs Job vs CronJob, under constraints | Design & Build |
| 03 | Multi-container patterns: native sidecar, init chain, adapter, ambassador | Design & Build |
| 04 | Volumes: emptyDir (memory, sizeLimit), projected, PVC, ephemeral volumes | Design & Build |
| 05 | Blue/green and canary with plain Services and labels; weighted canary by replica ratio | Deployment |
| 06 | Rolling updates under pressure: maxSurge/maxUnavailable, minReadySeconds, failed rollouts | Deployment |
| 07 | Helm: install, values, upgrade, rollback, template debugging, a broken chart | Deployment |
| 08 | Kustomize: components, patches, generators, replacements | Deployment |
| 09 | Probes: startup, liveness, readiness, gRPC/exec/http, and the failures each causes | Observability |
| 10 | Debugging: logs, events, `kubectl debug`, ephemeral containers, a crash that hides | Observability |
| 11 | API deprecations: find and migrate removed APIs in manifests | Observability |
| 12 | ConfigMaps and Secrets: every consumption style, updates, immutability | Environment & Security |
| 13 | SecurityContext and capabilities: non-root, read-only root, drop/add caps, fsGroup | Environment & Security |
| 14 | Requests, limits, LimitRange, ResourceQuota, and the Pods they reject | Environment & Security |
| 15 | ServiceAccounts, RBAC for an app, token projection, automount off | Environment & Security |
| 16 | CRDs and an operator: use custom resources an operator acts on | Environment & Security |
| 17 | Admission: what Pod Security Admission and a ValidatingAdmissionPolicy reject, and why | Environment & Security |
| 18 | Services: every type, named ports, headless, troubleshooting selectors | Networking |
| 19 | Ingress rules: hosts, paths, TLS, default backends | Networking |
| 20 | NetworkPolicies for an application: deny by default, allow exactly what it needs | Networking |

Plus 2 mock exams (120 min, 66%) and CKAD speed drills.

## CKS (v1.34): planned labs and cluster add-ons

Needs extra components on the cluster, installed by the labs themselves where
the exam expects you to (Falco, Trivy, kube-bench) and by setup where it doesn't
(an image registry, a vulnerable workload, a compromised node).

| # | Lab | Domain |
|---|---|---|
| 01 | CIS benchmark with kube-bench: fix API server, kubelet and etcd findings | Setup |
| 02 | Network policies that lock down cluster access, including node metadata and endpoints | Setup |
| 03 | Ingress with TLS, and verifying platform binaries (checksums of kubeadm, kubelet, kubectl) | Setup |
| 04 | RBAC least privilege: audit and cut an over-privileged setup | Hardening |
| 05 | ServiceAccounts: disable defaults, minimise rights, token audience | Hardening |
| 06 | Restrict API access: anonymous auth, NodeRestriction, admission, private endpoints | Hardening |
| 07 | Upgrade to fix a CVE without downtime | Hardening |
| 08 | Host footprint: remove packages and services, close ports, least-privilege users | System |
| 09 | AppArmor profiles for a workload | System |
| 10 | seccomp: RuntimeDefault, a custom Localhost profile | System |
| 11 | Pod Security Standards: enforce restricted, fix the workloads it rejects | Microservices |
| 12 | Secrets: encryption at rest (aescbc then KMS-style), rotation, reading them from etcd | Microservices |
| 13 | Isolation: RuntimeClass with gVisor, multi-tenancy | Microservices |
| 14 | Pod-to-Pod encryption: Calico WireGuard (or Istio mTLS) | Microservices |
| 15 | Minimal base images: shrink and harden a Containerfile | Supply chain |
| 16 | SBOM and scanning: Syft and Trivy, fail on criticals | Supply chain |
| 17 | Signed images: cosign, admission that verifies signatures, allowed registries | Supply chain |
| 18 | Static analysis: kubesec and KubeLinter on manifests | Supply chain |
| 19 | Audit logging: a policy that catches an attacker, then find them in the log | Runtime |
| 20 | Falco: detect a shell in a container, write a custom rule, investigate an incident | Runtime |
| 21 | Immutable containers: read-only root, no exec, detect drift | Runtime |

Plus 2 mock exams (120 min, 67%) and CKS speed drills.

## KCNA and KCSA: question banks

The quiz engine (web console, **Kubestronaut** tab) draws mock exams weighted by
domain, shuffles the options, never says how many answers a multi-select
question has, gives 20% less time than the real exam, and shows explanations
with documentation links only after you hand in. The banks live in the private
solutions repo (`questions/<track>/*.json`), so answers are never public.

Targets: **200 questions per track**, at least 25 per domain, each with an
explanation and an official reference. Hard by design: scenario questions,
multi-concept distractors, "select all that apply" without a count.
