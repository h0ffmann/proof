# Start here: reviewer

Read these before you review anything:

1. The norms in the `AGENTS.md` of your working folder: the box's, then ocean-waves-prove's.
2. `proof/AGENTS.md`, "Rules".
3. `proof/agda/src/WaveTheory/README.md`, "Assumptions to know".

## Limits of this box

- Your builds take the same lock as the provers', `flock "$OWPROVE_BUILD_LOCK"`, one at a time.
- No Docker and no GPU.
- You hold no claim. You never run `owprove next`, `submit` or `block`: the prover does.
