# Start here: prover

Read these before you change anything:

1. The norms in the `AGENTS.md` of your working folder: the box's, then ocean-waves-prove's.
2. `proof/AGENTS.md`, "Rules" and "Reproducible builds".
3. `proof/ocean-waves/README.md` and `proof/ocean-waves/openrig/README.md`.
4. `proof/agda/src/WaveTheory/README.md`, "Assumptions to know".

## Limits of this box

- The daemon and three seats share one memory budget (`MemoryHigh=3G` at piabrota2). One build at
  a time across the rig, under `flock "$OWPROVE_BUILD_LOCK"`, with one job.
- No Docker and no GPU. Lean, GHC and the other tools come from the repository's flake shells. If a
  shell does not start, block the item and say which.
- You read h0ffmann/proof through `owprove init`'s read token. You cannot push.
