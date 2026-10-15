#!/usr/bin/env bash
# Usage: ./ckad-grade.sh <question-id>|all [path/to/ckad-practice.json]
set -u
id="${1:?usage: $0 <question-id>|all [json]}"
json="${2:-$(dirname "$0")/ckad-practice.json}"
command -v jq >/dev/null || { echo "jq is required"; exit 2; }

# Git Bash rewrites /bin/sh-style arguments into Windows paths before they reach kubectl.exe.
export MSYS_NO_PATHCONV=1

# Windows builds of jq end lines with CRLF, which breaks the string comparisons in the checks.
jq() {
  command jq "$@" | tr -d '\r'
  return "${PIPESTATUS[0]}"
}
export -f jq

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$'\e[1m' DIM=$'\e[2m' GREEN=$'\e[32m' RED=$'\e[31m' RESET=$'\e[0m'
else
  BOLD="" DIM="" GREEN="" RED="" RESET=""
fi

limit=""
if command -v timeout >/dev/null; then
  limit="timeout 60"
fi

ids="$id"
if [ "$id" = all ]; then
  ids=$(jq -r '.scenario_questions[].id' "$json")
fi

for q in $ids; do
  if [ "$(jq --arg id "$q" '[.scenario_questions[] | select(.id == $id)] | length' "$json")" -eq 0 ]; then
    echo "unknown question id: $q"
    exit 2
  fi
  pass=0
  total=0
  now=$(date +%s)
  echo "${BOLD}$q${RESET}"
  while IFS= read -r g; do
    name=$(jq -r .check <<<"$g")
    cmd=$(jq -r .cmd <<<"$g")
    total=$((total + 1))
    # pipefail: a failing kubectl must fail the check even when jq/grep after it succeeds.
    # stdin from /dev/null: kubectl run -i / exec would otherwise swallow the loop's input.
    if $limit bash -o pipefail -c "$cmd" </dev/null >/dev/null 2>&1; then
      echo "  ${GREEN}✓ PASS${RESET}  $name"
      pass=$((pass + 1))
    else
      echo "  ${RED}✗ FAIL${RESET}  $name"
    fi
  done < <(jq -c --arg id "$q" '.scenario_questions[] | select(.id == $id) | .grade[]' "$json")
  if [ "$pass" -eq "$total" ]; then
    colour=$GREEN
  else
    colour=$RED
  fi
  echo
  echo "  ${BOLD}score  ${colour}$pass/$total${RESET}"
  # Written by lab.sh setup/random when the task was handed out.
  if [ -f ~/.ckad/start-"$q" ]; then
    target=$(jq -r --arg id "$q" '.scenario_questions[] | select(.id == $id) | .target_seconds' "$json")
    took=$((now - $(cat ~/.ckad/start-"$q")))
    if [ "$took" -le "$target" ]; then
      colour=$GREEN
    else
      colour=$RED
    fi
    echo "  ${BOLD}time   ${colour}$((took / 60))m$((took % 60))s${RESET} ${DIM}(target $((target / 60))m$((target % 60))s)${RESET}"
  fi
  if [ "$pass" -ne "$total" ]; then
    echo "  ${DIM}see how: ./lab.sh solution $q${RESET}"
  fi
  echo
done
