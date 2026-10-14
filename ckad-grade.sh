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
  echo "== $q"
  while IFS= read -r g; do
    name=$(jq -r .check <<<"$g")
    cmd=$(jq -r .cmd <<<"$g")
    total=$((total + 1))
    # pipefail: a failing kubectl must fail the check even when jq/grep after it succeeds.
    # stdin from /dev/null: kubectl run -i / exec would otherwise swallow the loop's input.
    if $limit bash -o pipefail -c "$cmd" </dev/null >/dev/null 2>&1; then
      echo "  PASS  $name"
      pass=$((pass + 1))
    else
      echo "  FAIL  $name"
    fi
  done < <(jq -c --arg id "$q" '.scenario_questions[] | select(.id == $id) | .grade[]' "$json")
  echo "  score: $pass/$total"
done
