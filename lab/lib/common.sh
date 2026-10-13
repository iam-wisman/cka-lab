# shellcheck shell=bash
# Shared helpers for the lab CLI, setup scripts and graders. Sourced, not run.
#
# Everything runs as `student` on the jump host. Nodes are reached over SSH
# with the lab key (~/.ssh/config maps cp1..nfs), and root work on them goes
# through passwordless sudo, exactly as in the exam environment.

LAB_HOME=${LAB_HOME:-/opt/cka-lab}
LAB_STATE=${LAB_STATE:-$HOME/.cka-lab}
LAB_SOLUTIONS=${LAB_SOLUTIONS:-/opt/cka-lab-solutions}
CONTROL_PLANES=(cp1 cp2 cp3)
WORKERS=(worker1 worker2)
K8S_NODES=("${CONTROL_PLANES[@]}" "${WORKERS[@]}")
API_ENDPOINT=k8s-api.cka.lab

# Grader-owned kubectl, so a student's broken or missing kubectl on the jump
# host never decides a grade.
GRADER_KUBECTL=$LAB_HOME/bin/kubectl
GRADER_KUBECONFIG=$LAB_STATE/grader.kubeconfig

c_red=$'\e[31m' c_green=$'\e[32m' c_yellow=$'\e[33m' c_blue=$'\e[34m' c_dim=$'\e[2m' c_bold=$'\e[1m' c_off=$'\e[0m'

die() { echo "${c_red}error:${c_off} $*" >&2; exit 1; }
info() { echo "${c_blue}::${c_off} $*"; }

# --- running things on nodes ------------------------------------------------

# on <node> <command...>   run as root on a node; stdout/stderr pass through.
on() {
  local node=$1 cmd; shift
  # Quote twice: once into a command line for bash -c, then that whole line
  # again, because ssh joins its arguments into a string for the remote shell.
  cmd=$(printf '%q ' "$@")
  ssh -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR "$node" "sudo bash -c $(printf '%q' "$cmd")"
}

# on_script <node> <<'EOF' ... EOF   run a root script on a node from stdin.
on_script() {
  local node=$1
  ssh -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR "$node" sudo bash -s
}

node_up() { ssh -o BatchMode=yes -o ConnectTimeout=3 -o LogLevel=ERROR "$1" true 2>/dev/null; }

# --- kubectl as cluster-admin for graders and setup scripts -----------------

# Fetch admin.conf from the first control plane that has one. The server is
# pointed at the API endpoint when it answers, else straight at a control plane
# whose API server answers, so a broken load balancer doesn't hide everything else.
grader_kubeconfig() {
  local cp server
  mkdir -p "$LAB_STATE"
  for cp in "${CONTROL_PLANES[@]}"; do
    if on "$cp" test -f /etc/kubernetes/admin.conf 2>/dev/null; then
      on "$cp" cat /etc/kubernetes/admin.conf >"$GRADER_KUBECONFIG.tmp" 2>/dev/null && break
    fi
  done
  [[ -s $GRADER_KUBECONFIG.tmp ]] || { rm -f "$GRADER_KUBECONFIG.tmp"; return 1; }
  mv "$GRADER_KUBECONFIG.tmp" "$GRADER_KUBECONFIG"
  chmod 600 "$GRADER_KUBECONFIG"

  for server in "https://$API_ENDPOINT:6443" https://10.10.10.11:6443 https://10.10.10.12:6443 https://10.10.10.13:6443; do
    if curl -sk --max-time 3 "$server/readyz" -o /dev/null -w '%{http_code}' 2>/dev/null | grep -qE '^(200|401|403)$'; then
      "$GRADER_KUBECTL" --kubeconfig "$GRADER_KUBECONFIG" config set-cluster \
        "$("$GRADER_KUBECTL" --kubeconfig "$GRADER_KUBECONFIG" config view -o jsonpath='{.clusters[0].name}')" \
        --server "$server" >/dev/null
      return 0
    fi
  done
  return 1
}

# kc ...   kubectl as cluster-admin (grader identity).
kc() { "$GRADER_KUBECTL" --kubeconfig "$GRADER_KUBECONFIG" --request-timeout=20s "$@"; }

# kcq <jsonpath-or-args...>  kubectl, stderr discarded, never fails the caller.
kcq() { kc "$@" 2>/dev/null || true; }

# Wait up to $1 seconds for "$@" (after the timeout) to succeed.
wait_for() {
  local timeout=$1; shift
  local end=$((SECONDS + timeout))
  until "$@" >/dev/null 2>&1; do
    (( SECONDS >= end )) && return 1
    sleep 3
  done
}

# helm_release <namespace> <release>   latest deployed Helm release as JSON
# ({name, version, chart:{metadata:{name,version}}, config:<user values>, info:{status}}),
# decoded from Helm's own storage Secret, so grading never depends on the
# student's helm binary.
helm_release() {
  kcq -n "$1" get secret -l "owner=helm,name=$2,status=deployed" -o json |
    python3 -c 'import sys, json, base64, gzip
items = json.load(sys.stdin).get("items", [])
if not items: sys.exit(1)
s = max(items, key=lambda i: int(i["metadata"]["labels"].get("version", 0)))
raw = base64.b64decode(base64.b64decode(s["data"]["release"]))
print(gzip.decompress(raw).decode() if raw[:2] == b"\x1f\x8b" else raw.decode())'
}

# release_values_match <namespace> <release> <values-file>
# True when the release's user-supplied values equal the file exactly (so the
# student installed from that file alone, without --set). Streams the release
# through stdin: a chart with CRDs can make it megabytes, too big for argv.
release_values_match() {
  helm_release "$1" "$2" | python3 -c 'import sys, json, yaml
want = json.load(sys.stdin).get("config", {})
have = yaml.safe_load(open(sys.argv[1])) or {}
sys.exit(0 if want and want == have else 1)' "$3"
}

# drill_ns <name>: a fresh namespace for a drill attempt. Drill namespaces carry the
# drill's id as a label, so the next attempt and `lab drill cleanup` find old ones.
drill_ns() {
  kc delete ns -l "cka-lab/drill=${GRADE_ID}" --wait=true --timeout=90s >/dev/null 2>&1
  kc create ns "$1" >/dev/null && kc label ns "$1" "cka-lab/drill=${GRADE_ID}" >/dev/null
  # Pods can't be created until the namespace's default ServiceAccount exists.
  for _ in $(seq 1 40); do kc -n "$1" get serviceaccount default >/dev/null 2>&1 && return 0; sleep 1.5; done
  die "namespace $1 has no default ServiceAccount: is kube-controller-manager running?"
}

# --- per-attempt values ------------------------------------------------------
#
# A lab can randomise names, ports and numbers for every attempt, so a retake tests
# skill rather than memory. Its `params` file declares them; `lab start` draws fresh
# values into $LAB_STATE/params/<lab>.env. The task text shows them through {{KEY}},
# and setup, grader, cleanup and reference solution all read the same file: it is
# loaded here automatically whenever GRADE_ID names the lab.

params_file() { echo "$LAB_STATE/params/${1:-${GRADE_ID:-none}}.env"; }
load_params() { local f; f=$(params_file "${1:-}"); if [[ -f $f ]]; then source "$f"; fi; }

# render <file> [id]: print the file with {{KEY}} and ${KEY} replaced by the attempt's values.
render() (
  f=$(params_file "${2:-}"); text=$(<"$1")
  if [[ -f $f ]]; then
    source "$f"
    for k in $(sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' "$f"); do
      text=${text//"{{$k}}"/${!k}}; text=${text//"\${$k}"/${!k}}
    done
  fi
  printf '%s\n' "$text"
)

[[ -n ${GRADE_ID:-} ]] && load_params
true
