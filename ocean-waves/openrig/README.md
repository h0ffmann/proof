# ocean-waves on OpenRig: proofs 24/7, one claimed module at a time

Status: draft. Nothing here has run ⚠. The owner asked on 2026-11-11 for "open spec rig" for
ocean-waves "in the same way was added for ww3-gpu, for 24/7 experiment".

This folder is the design and the spec files of an OpenRig rig, `ocean-waves-prove`. It runs on
the piabrota2 box next to the rigs that exist there. Its seats run Oh My Pi (`runtime: omp`) and
loop with no person present. A prover claims the next free item of [`queue.tsv`](queue.tsv), proves
it, asks a reviewer seat, and submits. A claim is an atomic file on the box, so two seats never
work the same item, and never edit the same Lean file at the same time. Accepted work collects on
one rolling branch that Hermes, the box's operator, pushes. The owner merges it when convenient.

## Where the shape comes from

The layout copies the OpenRig spec of the Kokkos port of WAVEWATCH III: WFIP-0007 and its
`openrig/` folder in h0ffmann/ww3-gpu at `8898772`
(<https://github.com/h0ffmann/ww3-gpu/blob/8898772/docs/WFIPs/WFIP-0007-openrig-port-factory.md>).
From there: three omp seats (two workers and one reviewer), a claim command with one lock file per
key, a heartbeat, `block` for work the rules forbid, a bundle in the outbox for Hermes, a keeper
that nudges idle workers, and a per-rig omp overlay of deny rules.

The box facts come from piabrota/nix-os at `57f96fa`, read 2026-11-11 (v):

- OpenRig runs as the unit `openrig`, `MemoryMax=4G`, `MemoryHigh=3G` at piabrota2, "at most three
  seats at the same time, in one rig" (`docs/OPENRIG.md`, "Limits").
- The box norms are `openrig/specs/agents/shared/guidance/norms.md`; an AgentSpec imports them as
  `local:../shared` and selects `shared:norms`.
- The claim model is the thesis rig's: `thesis fetch` makes the claim with `set -C`, takes over a
  claim older than 7200 s under a `mkdir` lock, and exits 3 when nothing is free
  (`docs/THESIS.md`, "One section, from claim to verdict").
- The chaceon port rig is always on, restored by `openrig-wf-keeper`, and the box runs one rig at a
  time (`docs/OPENRIG.md`, "wave-forecaster-dev"). That keeper "sends no task: an idle rig does no
  work".
- `hermes/omp.yml` refuses `git push`, `gh`, `curl`, `nix-env`, `nix profile` and installs for
  every omp seat. It does not refuse `nix develop`.

## What the rig works on

The Agda tree is ahead of the Lean package. `agda/src/WaveTheory/` (17 modules: moments, shoaling,
refraction, 2-D propagation, the time loop, WAVEWATCH III's frequency grid, unstructured meshes,
radiation stress, quadruplets, the DIA's interpolation weights, splitting, momentum) reuses the
Lean kernels but has no Lean twin. `ocean-waves/README.md`, "Next steps", also asks for a Haskell
port of the kernels checked against the Lean `#eval`s. These are many small items that share few
files: the case where seats in parallel pay.

[`queue.tsv`](queue.tsv) is the queue, in order. Its columns:

| column | meaning |
|---|---|
| `id` | the item, and its lock key |
| `kind` | `lean`: a core-Lean twin of an Agda module, same names with `-` as `_`, every theorem proved. `haskell`: the kernels in `Double`, `base` and `containers` only, with a spec check against `OceanWaves/Examples.lean` |
| `source` | the file the item follows |
| `target` | the file or folder the item writes; also a lock key |
| `depends` | items that must be accepted first |
| `status` | `todo`, or `waiting: <who>`. A waiting item is never claimed |

The owner adds rows at the end. `mathlib-tanh` waits for the owner, because Mathlib needs the
owner's agreement (`AGENTS.md`, rule 5).

## The claim command: `owprove`

A shell command in piabrota/nix-os (`owprove/`, as `thesis/` is), with no model and no network
except `git fetch`. Its state is in `/var/lib/openrig/work/ocean-waves-prove/`.

| command | does |
|---|---|
| `owprove next --as <seat>` | resumes the seat's own claim; else takes the first `todo` item whose `depends` are accepted and whose keys are free. `set -C` writes `claims/<key>.claim` for the `id` and the `target`, all or none. Exit 3 when nothing is free |
| `owprove bundle <id> --as <seat>` | writes a review bundle of the seat's branch for the reviewer |
| `owprove beat --as <seat>` | touches the claim. The role runs it at every step |
| `owprove release <id> --as <seat>` | gives the item back |
| `owprove block <id> --reason "<text>"` | moves it to `blocked/`. It is not tried again until the owner deletes the file |
| `owprove submit <id> --as <seat>` | only for the holder, after the reviewer's `accept`. Under `flock rolling.lock`: rebase onto the rolling tip, run the gates again, write `outbox/<id>.bundle` and `outbox/<id>.md`, write `accepted/<id>`, remove the claim |
| `owprove status` | each claim with its seat and heartbeat, the review in progress, the counts of accepted and blocked items, the rolling tip |

A claim with no heartbeat for 4 h is stale, and `next` takes it over under a `mkdir` lock.
Two files are lists that every `lean` item adds to: the import list `ocean-waves/lean/OceanWaves.lean`
and the table "What is proved" in `ocean-waves/README.md`. A seat adds its lines at the end. On a
rebase conflict in only those two files, `submit` keeps both sides (`git merge-file --union`) and
builds again. Any other conflict blocks the item.

## The loop

1. `owprove next`. Exit 3: say "queue empty" and stop.
2. Branch `hermes/ow-<id>` from the rolling tip in the seat's own clone.
3. Write the target. For `lean`: read the Agda module and write the Lean module with the same
   definitions and theorems. Core Lean only. No `sorry`, `admit` or `axiom`; `native_decide` only
   in a file named `*Examples.lean`.
4. Run the gates under `flock "$OWPROVE_BUILD_LOCK"`, one build at a time across the rig.
5. Send the commit to the reviewer. Fix what it reports. After the third round, `block`.
6. `owprove submit`, then go to 1.

## What the loop checks, and what it leaves to the owner

| check | in the loop | the owner, before the merge |
|---|---|---|
| `lake build` in `ocean-waves/lean`, inside `nix develop .#lean` | yes | |
| `bash scripts/lean-hygiene.sh` | yes | |
| `tools/text-checks/run.sh language` | yes | |
| `bash checks/invariants.sh` | yes | |
| the Haskell build with `-Wall` and its spec check (`haskell` items), inside `nix develop .#haskell` | yes | |
| review by the reviewer seat | yes | |
| `just check`, `just md-quality`, `just paper-check` | no | yes |

A Lean proof that builds is checked by Lean's kernel, so the evidence of an item is `lake build`
and the hygiene script, not the review. The review reads that the Lean statement says what the Agda
statement says: a proof of a weaker statement also builds.

## The files, and where they go in piabrota/nix-os

| file here | destination | what it is |
|---|---|---|
| [`specs/rigs/ocean-waves-prove/rig.yaml`](specs/rigs/ocean-waves-prove/rig.yaml) | `openrig/specs/rigs/ocean-waves-prove/rig.yaml` | pod `prove`: `prover-a`, `prover-b`, `reviewer`, all `runtime: omp` |
| [`specs/agents/ow-shared/`](specs/agents/ow-shared/guidance/norms.md) | `openrig/specs/agents/ow-shared/` | the norms of every seat for this repository |
| [`specs/agents/ow-prover/`](specs/agents/ow-prover/guidance/role.md) | `openrig/specs/agents/ow-prover/` | the prover: `agent.yaml`, its role, its start text |
| [`specs/agents/ow-reviewer/`](specs/agents/ow-reviewer/guidance/role.md) | `openrig/specs/agents/ow-reviewer/` | the reviewer, the same three files |
| [`omp/ocean-waves-prove.yml`](omp/ocean-waves-prove.yml) | `omp/ocean-waves-prove.yml` | the deny rules the seats add to `hermes/omp.yml` |

The specs live here while this is a draft. When nix-os has them, nix-os is their only copy and
this folder keeps `README.md` and `queue.tsv` only. The AgentSpecs import `local:../shared`, which
exists only in nix-os, so `rig agent validate` passes only there.

The nix-os side also needs `owprove` with its self-tests, a NixOS option
`piabrota.openrig.oceanWaves` (folders, a read token for this repository, the outbox, the keeper),
and a keeper `openrig-ow-keeper`: `openrig-wf-keeper` with this rig's name, which every 5 minutes
sends `rig send <seat>@ocean-waves-prove "Run owprove next and continue your loop."` to a prover
that holds no claim and whose last heartbeat is older than 20 minutes, and nothing when
`owprove next` would exit 3.

## Done when

- [ ] `owprove` passes its self-tests: two seats that race `next` on one item get one claim; a
  stale claim is taken over; `block` holds; an item never starts before its `depends`.
- [ ] `rig spec validate` and `rig up <spec> --plan` pass on the box.
- [ ] One supervised day: the peak of the unit `openrig` stays under `MemoryHigh` (`kvm4-health`),
  and the count of accepted items is written down.
- [ ] 72 h unattended, with the keeper restoring the rig after a restart.
- [ ] The first rolling PR passes `just check` on the owner's machine.

## Open questions, with the default

- **Which rig is always on.** The box runs one rig at a time, and chaceon's port rig is always on.
  Default: this rig's keeper is off until the owner turns it on.
- **Branch names.** Hermes pushes only `hermes/*`. This repository names a branch by its goal and
  refuses the words of a session in it (`Invariants.lp`, rule 3), which `hermes/ow-<id>` meets.
  Default: `hermes/ow-<id>` per item and `hermes/ow-rolling` for the rolling PR.
- **No trailers.** This repository refuses `Co-Authored-By` and every other attribution trailer
  (`AGENTS.md`, "No trailers, no attribution"). Hermes's commits carry none, which fits. Default:
  `submit` writes a plain message, with a `Tested:` line in the body.
- **Lean on the box.** The gates need `nix develop .#lean`, which fetches the Lean release and the
  flake's inputs. Default: the NixOS option builds the `lean` shell of this flake into the seat
  profile, so a seat fetches nothing ⚠.
- **The model.** Every seat on the box uses `anthropic/claude-sonnet-5-5`. A stronger model may
  close more proofs. Default: Sonnet; a member's `model` can name another, which is the owner's call.

## Not checked ⚠

- No `rig spec validate`, `rig agent validate` or `rig up --plan` ran on these files.
- The memory of `lake build` and of the Haskell build on the box. The rig caps it at one build.
  A clean `lake build` of `OceanWaves` in a cloud container (4 vCPU, 15 GiB, default Lean threads)
  took 10 s, with a sampled peak of about 1.3 GiB for `lake` and its children (`ps` every second,
  so a short peak can be missed; 2026-11-11). With the daemon and three seats (about 1.2 GiB, the
  figures of `hermes-omp/references/openrig-seats.md` in nix-os) that is about 2.5 GiB, under
  `MemoryHigh`. `LEAN_NUM_THREADS=1` should lower it; not measured.
- Whether the seat can run `nix develop` inside the unit's sandbox.
- Whether omp takes the overlay of `omp/ocean-waves-prove.yml` as a second config file
  (the same open point as the WFIP this copies).
- How many items a day the rig closes, and subscription rate limits.
