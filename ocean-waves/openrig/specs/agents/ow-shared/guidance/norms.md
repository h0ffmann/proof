# Rules of every ocean-waves-prove seat

These rules add to the rules of every piabrota seat. They apply to work on the `ocean-waves/`
topic of h0ffmann/proof: the theory and the kernels of a spectral wave model, proved in core Lean
and in Agda. A human or Hermes can change them only through a pull request to piabrota/nix-os.

## The repository binds you

- `owprove init` made `proof/` in your working folder: a clone of h0ffmann/proof with a read-only
  token, on the rolling branch. Fetch with `git -C proof fetch`. Never clone again by hand.
- Before any change, read `proof/AGENTS.md`, `proof/ocean-waves/README.md`,
  `proof/ocean-waves/openrig/README.md` and `proof/agda/src/WaveTheory/README.md`. They bind you.
  omp does not load them by itself here, because your working folder is not the clone.
- Every file is in English (`AGENTS.md`, "Language"). Code comments follow ASD-STE100.
- Touch only the target of your item, the end of `ocean-waves/lean/OceanWaves.lean` (one import
  line) and the end of the table "What is proved" in `ocean-waves/README.md`. Never edit `agda/`,
  `vendor/`, `flake.nix`, `flake.lock`, `nix/`, `.github/`, `Invariants.lp` or another topic.

## The queue is the only source of work

- Work only on the item `owprove next` gave you. Run `owprove beat --as <seat>` after each step,
  so your claim stays alive. A claim with no beat for 4 hours goes to another seat.
- Never edit `ocean-waves/openrig/queue.tsv`, and never touch the files of `owprove`'s state.
- `owprove next` exits 3 when nothing is free. Then say "queue empty" and stop. Do not invent work.

## Proofs are complete

- No `sorry`, `admit` or `axiom`, anywhere. `native_decide` only in a file named `*Examples.lean`.
- Core Lean only: no Mathlib, no new package, no new `require` in `lakefile.toml`. A proof that
  needs Mathlib is blocked: `owprove block <id> --reason "needs Mathlib: <what>"`.
- A twin states what the Agda module states. Never weaken a statement, add a premise or drop a
  theorem so that it builds. If a statement does not hold or does not fit core Lean, block the item
  and say which theorem and why.
- Names follow the Agda module, with `-` written as `_`. A Lean name that differs gets one line in
  the module's header comment that says why.

## The gates

Run each under `flock "$OWPROVE_BUILD_LOCK"`, one build at a time across the rig, with
`nice -n 10`:

- `nix develop .#lean --command bash -c 'cd ocean-waves/lean && lake build'`: no error.
- `bash scripts/lean-hygiene.sh`: passes.
- `tools/text-checks/run.sh language`: OK.
- `bash checks/invariants.sh`: ok.
- For a `haskell` item: the build with `-Wall` and no warning, and the spec check, every line `OK`,
  inside `nix develop .#haskell`.

You do not run `just check`, `just md-quality` or `just paper-check`: the owner runs them on the
rolling branch. Name only the commands you ran in a `Tested:` line.

## Memory

The daemon and three seats share the unit's memory. One build at a time, with one job. If a build
is killed for memory, block the item with the reason and tell the reviewer. Do not retry it in a
loop.

## Branches and handoff

- Your branch is `hermes/ow-<id>` from the rolling tip. A branch name never carries the words
  claude, session, thread or cmsg (`Invariants.lp`, rule 3).
- A commit message is a subject, a body that says what and why, and a `Tested:` line. No trailer:
  no `Co-Authored-By`, `Signed-off-by` or any attribution (`AGENTS.md`, "No trailers, no
  attribution"). No other repository's name or URL in a commit message.
- You never push. `owprove submit` writes the bundle in `$OWPROVE_OUTBOX`; Hermes fetches it.

## Never

- Never weaken a theorem to make it build, and never skip a gate.
- Never commit a PDF or a build folder (`.lake/`).
- Never print the token that `owprove init` uses.
