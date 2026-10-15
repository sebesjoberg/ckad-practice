# CKAD practice

Exam-style CKAD scenarios on local kind clusters, graded as strictly as the real exam.

```bash
./lab.sh up              # two clusters: cluster1, cluster2
./lab.sh random          # random unseen question, prepared, task shown (filter: ./lab.sh random netpol)
./lab.sh grade           # grade it, with your time against the target
./lab.sh hint            # stuck: where to look + traps
./lab.sh solution        # fastest solution + how to verify
./lab.sh pin             # keep the task pinned in a tmux pane above your shell (./lab.sh unpin closes it)
./lab.sh drill           # 10 rapid-fire command drills
```

Needs docker, kind, kubectl, jq, helm and bash. WSL works best. In Git Bash, run `export MSYS_NO_PATHCONV=1`
first and give kubectl/helm local files as relative paths (`./file`).

To practise with Claude as examiner instead, give it `ckad-practice.json` and say *"You are my CKAD examiner. Follow tutor_instructions."*
