# CKAD practice

Exam-style CKAD scenarios on local kind clusters, graded as strictly as the real exam.

```bash
./lab.sh up              # two clusters: cluster1, cluster2
./lab.sh random          # random unseen question, prepared, task shown (filter: ./lab.sh random netpol)
./ckad-grade.sh <id>     # grade it, incl. time vs target
```

Needs docker, kind, kubectl, jq, helm and bash. WSL works best. In Git Bash, run `export MSYS_NO_PATHCONV=1`
first and give kubectl/helm local files as relative paths (`./file`).

To practise with Claude, give it `ckad-practice.json` and say *"You are my CKAD examiner. Follow tutor_instructions."*
