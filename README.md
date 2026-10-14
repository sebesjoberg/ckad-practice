# CKAD practice

Exam-style scenarios with strict auto-grading, built from a failed mock exam. The goal is speed with
imperative `kubectl` and the habits that cost points: right context, exact names, every sub-step, verify.

| File | What |
|---|---|
| `ckad-practice.json` | 37 scenarios, 58 speed drills, tutor instructions for a Claude examiner, learner profile |
| `lab.sh` | Local practice clusters (kind) and per-question setup |
| `ckad-grade.sh` | Grades a question as harshly as the real grader |

## Requirements

docker, kind, kubectl, jq, bash (WSL, Linux, macOS or Git Bash). `helm` for the helm questions.

## Usage

```bash
./lab.sh up                 # cluster1 (kindnet) + cluster2 (Calico, enforces NetworkPolicy), metrics-server on both
./lab.sh list               # question ids, cluster, target time
./lab.sh setup cron-01      # prepares the scenario; leaves your current context alone
# ... solve it ...
./ckad-grade.sh cron-01     # PASS/FAIL per check + score
./lab.sh reset              # start over from clean clusters
./lab.sh down               # delete the clusters
```

## With a Claude examiner

Give a Claude session `ckad-practice.json` and say: *"You are my CKAD examiner. Follow tutor_instructions."*
It presents one question at a time, times you, and asks for the grader output when you are done.

## Grading

Checks pin the question's cluster with `--context`, compare exact values (`1.20.0` is not `v1.20.0`)
and test behaviour where the exam does (curl from a pod, `exec`, `auth can-i`, blocked traffic).
Some checks are "don't break it" guards (e.g. the Service selector must stay unchanged) and pass
straight after setup.

In Git Bash both scripts set `MSYS_NO_PATHCONV=1`. Do the same in your own shell, or Git Bash rewrites
arguments like `/bin/sh` into Windows paths before they reach `kubectl.exe`:

```bash
export MSYS_NO_PATHCONV=1
```
