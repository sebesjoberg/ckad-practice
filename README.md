# CKAD practice

Exam-style CKAD scenarios on local kind clusters, graded as strictly as the real exam.

```bash
./lab.sh up              # two clusters: cluster1, cluster2
./lab.sh setup cron-01   # prepare a question
./ckad-grade.sh cron-01  # grade it
```

Needs docker, kind, kubectl, jq, helm and bash. In Git Bash, run `export MSYS_NO_PATHCONV=1` first.

To practise with Claude, give it `ckad-practice.json` and say *"You are my CKAD examiner. Follow tutor_instructions."*
