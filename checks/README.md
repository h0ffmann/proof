# checks/

One script per feature: `checks/<feature>.sh`, run from the repository root, exit code 0 when the
check holds. `just check`, `just checks` and `.github/workflows/check.yml` run every script here, so
a new check needs no change to a shared file. Pip packages a check needs go in
`checks/<feature>.requirements.txt`; the workflow installs every such file.

```bash
just checks              # every check
just checks port-audit   # one check
```
