#!/usr/bin/env bash
# Local practice clusters for ckad-practice.json.
#
#   ./lab.sh up                 create cluster1 + cluster2 (kind)
#   ./lab.sh down               delete both clusters and their contexts
#   ./lab.sh reset              down + up
#   ./lab.sh setup <id>         prepare the scenario for one question
#   ./lab.sh list               list question ids
set -euo pipefail
cd "$(dirname "$0")"

JSON=ckad-practice.json
CALICO_VERSION=v3.28.2
METRICS_SERVER_VERSION=v0.7.2

# Git Bash rewrites /bin/sh-style arguments into Windows paths before they reach kubectl.exe.
export MSYS_NO_PATHCONV=1

# Windows builds of jq end lines with CRLF.
jq() {
  command jq "$@" | tr -d '\r'
  return "${PIPESTATUS[0]}"
}
export -f jq

need() {
  for tool in "$@"; do
    command -v "$tool" >/dev/null || { echo "missing tool: $tool"; exit 1; }
  done
}

create_cluster() {
  local name=$1 calico=$2
  if kind get clusters 2>/dev/null | tr -d '\r' | grep -qx "$name"; then
    echo "== $name already exists"
    return
  fi
  if kubectl config get-contexts -o name | tr -d '\r' | grep -qx "$name"; then
    echo "a kube context named '$name' exists but is not a lab cluster - refusing to touch it"
    exit 1
  fi

  echo "== creating $name (calico: $calico)"
  # podSubnet matches Calico's default IP pool
  kind create cluster --name "$name" --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: $calico
  podSubnet: 192.168.0.0/16
EOF
  kubectl config rename-context "kind-$name" "$name" >/dev/null

  if [ "$calico" = true ]; then
    kubectl --context "$name" apply -f "https://raw.githubusercontent.com/projectcalico/calico/$CALICO_VERSION/manifests/calico.yaml" >/dev/null
  fi

  kubectl --context "$name" apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/$METRICS_SERVER_VERSION/components.yaml" >/dev/null
  # kind's kubelets use self-signed serving certificates
  kubectl --context "$name" -n kube-system patch deploy metrics-server --type=json \
    -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null

  kubectl --context "$name" wait --for=condition=Ready nodes --all --timeout=300s
}

up() {
  need docker kind kubectl
  # cluster2 runs Calico so NetworkPolicies are enforced there (netpol-02 tests real traffic)
  create_cluster cluster1 false
  create_cluster cluster2 true
  kubectl config use-context cluster1 >/dev/null
  echo
  echo "Ready. Contexts: cluster1, cluster2 (current: cluster1)."
  echo "Next: ./lab.sh setup <question-id>   then solve it   then ./ckad-grade.sh <question-id>"
}

down() {
  need kind kubectl
  for name in cluster1 cluster2; do
    kind delete cluster --name "$name"
    kubectl config delete-context "$name" >/dev/null 2>&1 || true
  done
  docker rm -f ext-web ext-api >/dev/null 2>&1 || true
}

setup() {
  need jq kubectl
  local id=$1 ctx kubeconfig
  ctx=$(jq -r --arg id "$id" '.scenario_questions[] | select(.id == $id) | .context' "$JSON")
  if [ -z "$ctx" ]; then
    echo "unknown question id: $id (see ./lab.sh list)"
    exit 1
  fi

  # Run the setup against the question's cluster through a private kubeconfig copy,
  # so the learner's current context is left alone - switching it is part of the drill.
  kubeconfig=$(mktemp)
  trap 'rm -f "$kubeconfig"' RETURN
  if command -v cygpath >/dev/null; then
    # kubectl.exe cannot open MSYS paths like /tmp/...
    kubeconfig=$(cygpath -m "$kubeconfig")
  fi
  kubectl config view --raw > "$kubeconfig"
  if [ "$ctx" != local ]; then
    KUBECONFIG="$kubeconfig" kubectl config use-context "$ctx" >/dev/null
  fi

  echo "== setup $id (on $ctx)"
  while IFS= read -r entry; do
    local cmd
    cmd=$(jq -r . <<<"$entry")
    case "$cmd" in
      "("*)
        echo "   note: $cmd"
        continue
        ;;
    esac
    # Output only, not the commands: some setups plant bugs the learner has to find.
    if ! KUBECONFIG="$kubeconfig" bash -o pipefail -c "$cmd" </dev/null 2>&1 | sed 's/^/   /'; then
      echo "   ! a setup step failed (already set up? './lab.sh reset' starts clean)"
    fi
  done < <(jq -c --arg id "$id" '.scenario_questions[] | select(.id == $id) | .setup[]' "$JSON")

  echo
  echo "Task for $id is ready. Your current context is still: $(kubectl config current-context)"
}

list() {
  need jq
  jq -r '.scenario_questions[] | "\(.id)\t\(.context)\t\(.target_seconds)s\t\(.domain)"' "$JSON" | column -t -s $'\t'
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  reset) down; up ;;
  setup) setup "${2:?usage: ./lab.sh setup <question-id>}" ;;
  list) list ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
