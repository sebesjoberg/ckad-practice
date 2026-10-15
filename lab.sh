#!/usr/bin/env bash
# Local practice clusters for ckad-practice.json.
#
#   ./lab.sh up                 create cluster1 + cluster2 (kind)
#   ./lab.sh down               delete both clusters and their contexts
#   ./lab.sh reset              down + up
#   ./lab.sh random [filter]    pick a question you have not had yet, prepare it, show the task
#                               (filter matches id or domain, e.g. netpol, helm, security)
#   ./lab.sh setup <id>         prepare a specific question and show the task
#   ./lab.sh grade [id]         grade the current (or given) question
#   ./lab.sh hint [id]          where to look in the docs + the traps
#   ./lab.sh solution [id]      fastest solution and how to verify it
#   ./lab.sh task [id]          show the task again
#   ./lab.sh drill [n]          n speed drills (default 10): type the command, then compare
#   ./lab.sh list               list question ids
set -euo pipefail
cd "$(dirname "$0")"

JSON=ckad-practice.json
STATE=~/.ckad
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

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$'\e[1m' DIM=$'\e[2m' CYAN=$'\e[36m' RED=$'\e[31m' RESET=$'\e[0m'
else
  BOLD="" DIM="" CYAN="" RED="" RESET=""
fi

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
  echo "Next: ./lab.sh random   then solve it   then ./ckad-grade.sh <question-id>"
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
  if command -v cygpath >/dev/null; then
    # kubectl.exe cannot open MSYS paths like /tmp/...
    kubeconfig=$(cygpath -m "$kubeconfig")
  fi
  kubectl config view --raw > "$kubeconfig"
  if [ "$ctx" != local ]; then
    KUBECONFIG="$kubeconfig" kubectl config use-context "$ctx" >/dev/null
  fi

  echo "${DIM}preparing $id on $ctx ...${RESET}"
  while IFS= read -r entry; do
    local cmd
    cmd=$(jq -r . <<<"$entry")
    case "$cmd" in
      "(tutor"* | "(the tutor"*)
        continue
        ;;
      "("*)
        echo "${DIM}  │ $cmd${RESET}"
        continue
        ;;
    esac
    # Output only, not the commands: some setups plant bugs the learner has to find.
    local out status=0
    out=$(KUBECONFIG="$kubeconfig" bash -o pipefail -c "$cmd" </dev/null 2>&1) || status=$?
    if [ "$status" -ne 0 ] && ! grep -v AlreadyExists <<<"$out" | grep -q .; then
      echo "${DIM}  │ (already set up)${RESET}"
      continue
    fi
    if [ -n "$out" ]; then
      sed "s/^/${DIM}  │ /; s/\$/${RESET}/" <<<"$out"
    fi
    if [ "$status" -ne 0 ]; then
      echo "${RED}  ! a setup step failed - './lab.sh reset' starts from clean clusters${RESET}"
    fi
  done < <(jq -c --arg id "$id" '.scenario_questions[] | select(.id == $id) | .setup[]' "$JSON")
  rm -f "$kubeconfig"

  mkdir -p "$STATE"
  date +%s > "$STATE/start-$id"
  echo "$id" > "$STATE/current"
  echo
  task "$id"
}

task() {
  need jq
  local id=$1 q width left right gap line first rest
  q=$(jq -c --arg id "$id" '.scenario_questions[] | select(.id == $id)' "$JSON")
  if [ -z "$q" ]; then
    echo "unknown question id: $id (see ./lab.sh list)"
    exit 1
  fi

  width=$(tput cols 2>/dev/null || echo 80)
  if [ "$width" -gt 96 ]; then
    width=96
  fi
  left=$(jq -r '"\(.id)  ·  \(.domain)"' <<<"$q")
  right=$(jq -r '"weight \(.weight)  ·  target \(.target_seconds / 60 | floor):\(.target_seconds % 60 | tostring | if length < 2 then "0" + . else . end)"' <<<"$q")
  gap=$((width - ${#left} - ${#right} - 2))
  if [ "$gap" -lt 2 ]; then
    gap=2
  fi

  hr "$width"
  printf ' %s%s%s%*s%s\n' "$BOLD" "$left" "$RESET" "$gap" "" "$right"
  hr "$width"
  echo

  if [ "$(jq -r .context <<<"$q")" != local ]; then
    echo "  ${BOLD}${CYAN}kubectl config use-context $(jq -r .context <<<"$q")${RESET}"
    echo
  fi

  # "(1) ... (2) ..." steps go on their own lines with a hanging indent.
  while IFS= read -r line; do
    if [[ $line =~ ^\([0-9]+\) ]]; then
      first="    " rest="        "
    else
      first="  " rest="  "
    fi
    if [ -z "$line" ]; then
      echo
      continue
    fi
    fold -s -w $((width - ${#rest})) <<<"$line" | sed "1s/^/$first/; 2,\$s/^/$rest/"
  done < <(jq -r '.task | gsub(": \\((?<n>[0-9]+)\\) "; ":\n(\(.n)) ") | gsub("; \\((?<n>[0-9]+)\\) "; "\n(\(.n)) ")' <<<"$q")

  echo
  echo "  ${DIM}done?  ./lab.sh grade     stuck?  ./lab.sh hint  ·  ./lab.sh solution"
  echo "  your context now: $(kubectl config current-context 2>/dev/null)${RESET}"
  echo
}

current_id() {
  local id=${1:-}
  if [ -z "$id" ] && [ -f "$STATE/current" ]; then
    id=$(cat "$STATE/current")
  fi
  if [ -z "$id" ]; then
    echo "no current question - start one with ./lab.sh random" >&2
    exit 1
  fi
  echo "$id"
}

# Prints one section of a question: a heading, then each array entry as a block.
section() {
  local q=$1 field=$2 title=$3 style=$4 entry
  if [ "$(jq -r --arg f "$field" '.[$f] | if type == "array" then length elif . == "-" or . == null then 0 else 1 end' <<<"$q")" -eq 0 ]; then
    return
  fi
  echo "  ${BOLD}$title${RESET}"
  while IFS= read -r entry; do
    case $style in
      cmd) jq -r . <<<"$entry" | sed "1s/^/    \$ ${CYAN}/; 2,\$s/^/      ${CYAN}/; s/\$/${RESET}/" ;;
      bullet) jq -r . <<<"$entry" | fold -s -w 88 | sed "1s/^/    • /; 2,\$s/^/      /" ;;
    esac
  done < <(jq -c --arg f "$field" '.[$f] | if type == "array" then .[] else . end' <<<"$q")
  echo
}

question() {
  jq -c --arg id "$1" '.scenario_questions[] | select(.id == $id)' "$JSON"
}

hint() {
  need jq
  local q
  q=$(question "$1")
  echo
  section "$q" docs_search "Where to look" bullet
  section "$q" traps "Watch out for" bullet
}

solution() {
  need jq
  local q
  q=$(question "$1")
  echo
  section "$q" fastest_solution "Fastest solution" cmd
  section "$q" verify "Verify" cmd
  section "$q" traps "Traps" bullet
}

drill() {
  need jq shuf
  local n=${1:-10} entry prompt answer typed i=0 right=0 verdict
  echo "${DIM}Type the command from memory and press Enter (empty = skip). Then judge yourself: y/n.${RESET}"
  while IFS= read -r entry <&3; do
    i=$((i + 1))
    prompt=$(jq -r .prompt <<<"$entry")
    answer=$(jq -r .answer <<<"$entry")
    echo
    echo "${BOLD}$i/$n${RESET}  $prompt"
    read -r -p "  \$ " typed
    echo "  ${CYAN}$answer${RESET}"
    read -r -p "  right? [y/N] " verdict
    if [ "$verdict" = y ] || [ "$verdict" = Y ]; then
      right=$((right + 1))
    fi
  done 3< <(jq -c '.speed_drills[]' "$JSON" | shuf -n "$n")
  echo
  echo "${BOLD}$right/$i right${RESET}"
}

hr() {
  local i out=""
  for ((i = 0; i < $1; i++)); do
    out+="━"
  done
  echo "${CYAN}${out}${RESET}"
}

random_question() {
  need jq shuf
  local filter=${1:-} candidates unseen id
  candidates=$(jq -r --arg f "$filter" '.scenario_questions[]
    | select($f == "" or ((.id + " " + .domain) | ascii_downcase | contains($f | ascii_downcase))) | .id' "$JSON")
  if [ -z "$candidates" ]; then
    echo "no question matches '$filter' (see ./lab.sh list)"
    exit 1
  fi
  mkdir -p "$STATE"
  touch "$STATE/seen"
  unseen=$(grep -vxF -f "$STATE/seen" <<<"$candidates" || true)
  if [ -z "$unseen" ]; then
    echo "(you have had every matching question - starting the round again)"
    grep -vxF -f <(echo "$candidates") "$STATE/seen" > "$STATE/seen.tmp" || true
    mv "$STATE/seen.tmp" "$STATE/seen"
    unseen=$candidates
  fi
  id=$(shuf -n 1 <<<"$unseen")
  echo "$id" >> "$STATE/seen"
  setup "$id"
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
  task | grade | hint | solution)
    # assigned first: set -e does not stop on a failing $(...) used as an argument
    id=$(current_id "${2:-}")
    case $1 in
      task) task "$id" ;;
      grade) exec ./ckad-grade.sh "$id" ;;
      hint) hint "$id" ;;
      solution) solution "$id" ;;
    esac
    ;;
  drill) drill "${2:-10}" ;;
  random) random_question "${2:-}" ;;
  list) list ;;
  *) sed -n '2,16p' "$0"; exit 1 ;;
esac
