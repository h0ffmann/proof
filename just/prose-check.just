# The ASD-STE100 and PTC rules in Agda (tools/prose-check/); also in `just check`
prose:
    bash checks/prose-check.sh

# The sentences a reader must judge for ASD-STE100 (the -ing form and the passive voice)
prose-review *files:
    tools/prose-check/run.sh ste --review {{files}}
