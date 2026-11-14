# Plan: WAVEWATCH III through Agda and Triton

This plan says how the pipeline of this folder (an Agda specification, Triton kernels printed
from it, proofs between the two) grows from one reduced model step to the routines of WAVEWATCH
III (WW3). It has milestones, and every milestone has checkpoints. Each checkpoint is one of
three kinds, and only the kind named counts as done:

| Mark | Kind | Means | Checked by |
|---|---|---|---|
| **P** | proved | the meaning of the printed kernel over ℚ is the Agda specification, for every input | `bash checks/agda.sh` (`--safe`, no postulate) |
| **T** | tested in Triton | the printed kernel, run by Triton in float32, agrees with the exact values within the rounding budget of `check.py` | `bash checks/ocean-triton.sh` |
| **W** | verified against WW3 | the Agda specification is the WW3 routine: the same formula as `model/src/<file>.F90` at a pinned WW3 commit, and the Triton kernel agrees with the Fortran routine on inputs captured from a WW3 run | a capture and a replay (milestone M5) |

**W is the claim "matches WW3", and no kernel has it yet.** The physics of `agda/src/OceanWaves/`
is a reduced form of a spectral model: one geographic dimension, Snyder-type wind input, WAM
Cycle 4 whitecapping with the k⁻¹ moment instead of k^(-1/2), a tridiagonal quadruplet exchange
in place of the DIA, a Padé tanh, and exact rationals. It is the right shape for WW3's time
step, but not WW3's numbers. Milestone M4 replaces it, routine by routine.

## Status on 2026-11-14

| Milestone | State | P | T | W |
|---|---|---|---|---|
| M0 The kernels of one reduced step | done | 12 of 12 | 12 of 12 (CPU interpreter) | 0 |
| M1 The step without host-side physics | done | 6 of 6 | 6 of 6 (CPU interpreter) | 0 |
| M2 Space: 2-D propagation and the time loop | done (step 4 in M3) | 2 programs (5 kernels) | 2 programs (CPU interpreter) | 0 |
| M3 Spectral space and other grids | done, except steps 2b and 3b | 5 kernels, 2 programs | 5 kernels, 2 programs (CPU interpreter) | 0 |
| M4 WW3's own source terms | W3SBT1 and W3SNL1 done; W3SDB1, ST4 and W3SRCE open | 2 routines (2 + 11 kernels) | 2 routines (CPU interpreter) | 2 routines (M5) |
| M5 Verification against WW3 | steps 1 to 3 done in this change for W3SNL1 and W3SBT1; step 4 open | — | — | W3SNL1, W3SBT1: bit for bit on 3 captures |
| M6 GPU runs and timing | planned | — | 0 on a GPU | — |

## M0: the kernels of one reduced step (done)

Checkpoints:

- [x] P, T: `advect`, `advect_cg` (upwind, `OceanWaves.Advection`), with positivity under CFL.
- [x] P, T: `sigma2`, `group_speed` (`OceanWaves.Dispersion`, Padé tanh).
- [x] P, T: `wind_rate`, `ds_rate` with the reduce kernels `energy_total`, `energy_over_sigma`,
  `energy_over_k` (`OceanWaves.Sources`).
- [x] P, T: `lin_step`, `euler_step`, `source_step` (the limiter).
- [ ] W: none. The formulas are the reduced ones above.

## M1: the step without host-side physics (done)

Before M1, the host had to compute S_nl and the wavenumber. Now each has a kernel.

- [x] P: `snl-stencil`: S_nl in bin j is G(j + 1) + G(j − 1) − 2 G(j), with G the exchange amount
  gated to interior centres, for every n, d and j. The sum over all centres becomes a three-point
  stencil, which a GPU lane computes from three loads. `snlK-conserves`: the stencil keeps the
  total action.
- [x] P: `source_step_snl`: the source step with S_nl computed in the kernel.
- [x] P: `wavenumber`, a loop kernel with two registers per lane, equals
  `OceanWaves.Bisection.waveNumber` for every number of steps (`wavenumberK-sound`, by induction
  on the steps).
- [x] P: `sxx`, `sxy`, `syy` (`WaveTheory.RadiationStress`), the WW3 output fields SXX, SXY,
  SYY, with the direction-free trace restated (`stressK-trace`).
- [x] T: all six agree with the exact values on 40 lanes (20 bisection steps).
- [ ] W: none.

## M2: space (done; step 4 done in M3)

Goal: one full time step of a 2-D regular grid on the device, with the host only launching
kernels.

1. A 2-D read: `OceanTriton.Grid.Expr2`, one lane per cell, `x = i % nx`, `y = i // nx`. The
   periodic reads `west` and `south` are the upstream values of `advectPeriodic`, so no `mod`
   on ℕ enters a proof (the risk named in the first version of this plan).
   - [x] P: `sweep_x`, `sweep_y` equal `sweepX`, `sweepY` by `refl` (`sweepXK-sound`,
     `sweepYK-sound`); `run2D-total`, `run2D-nonneg` and `run2D-le` restated for the program's
     meaning (`prop2D-total`, `prop2D-nonneg`, `prop2D-le`).
   - [x] T: a 9 × 7 grid, 3 runs with cx = 2/5 and cy = 1/3: every cell and the total in
     float32 within the budget.
2. A spectral dimension: y is the bin j, so one lane per (cell, bin). `propagate` reads each
   bin's Courant number from a buffer that the host fills once with `ActionBalance.μ`.
   - [x] P, T: inside the model program below.
3. The chain of launches: `Program`, a list of launches on named buffers, with a meaning that
   runs them in order (`steps`) and k times (`repeat`).
   - [x] P: `model-step`: the meaning of the program `propagate`, `exchange`, `sources` is
     `OceanWaves.ActionBalance.step` at every cell and bin. `model-run`: for k runs it is
     `WaveTheory.TimeLoop.run`. So `run-nonneg` holds for it (`model-nonneg`). `prop2D-run`: the
     2-D program run k times is `run2D`, as an equality of fields.
   - [x] T: `check_grid.py` runs the programs (each launch into a fresh buffer), not single
     kernels: `model` on 5 cells and 6 bins, 2 runs, with the limiter at both bounds.
   - Scope: the model's rates are per bin and the exchange amount is κ N (`ModelConfig`), a
     special case of `StepConfig`, whose rates are functions of the local spectrum.
     `run-total-le` is not restated: its hypotheses are about `TimeLoop`'s own terms, and
     `model-run` carries them over pointwise.
4. [x] The fused whitecapping in one launch: done in M3, step 4.

## M3: spectral space and other grids (done in this change, except 2b and 3b)

A new kernel language, `OceanTriton.Gather`, adds what M0's `Expr` cannot say: a read through
an index array (`gat`), a padded row of an edge list (`rowW`, `rowG`), a product repeated a
per-lane number of times (`rep`, for W3SNL1's tail), and sums over the lanes computed in the
same launch (a fused kernel). Its programs (`ProgramG`) carry index arrays and lane counts per
launch. `OceanTriton.EmitGather` prints it to `gather.py`; `check_gather.py` runs it.

1. Refraction and shoaling (`OceanTriton.Shallow`).
   - [x] P: `snell`, `shoal`, `break_cap` equal `WaveTheory.Refraction.snell`,
     `WaveTheory.Shoaling.shoal` and `breakCap` by `refl`; `shoalK-flux` (energy flux kept) and
     `breakCapK-le` restated for the kernels.
   - [x] T: 40 lanes each in `kernels.py`, the cap active on some lanes and not on others.
   - WW3 turns refraction into advection in θ (its `W3KTP` routines, not yet read at a pin);
     step 3 gives the split form that such an advection enters.
2. Unstructured grids (`OceanTriton.Mesh`): a step on a mesh as a gather over each node's
   padded rows of outgoing fractions and incoming edges. A gather keeps the order of the sum
   fixed; a scatter with atomics would not.
   - [x] P: `meshK-sound`: the kernel is `meshStep` for every edge list whose degrees fit the
     rows (`MaxDeg`); `mesh-run`: k launches are `meshRun`; `mesh-total` and `mesh-nonneg`
     restated.
   - [x] T: a 6-node mesh (a ring and three chords, rows of 3 with padding), 4 steps.
   - [ ] 2b. T on a mesh of `triangle-grids/`. Open.
3. Splitting (`OceanTriton.Shallow`, `strang`): half a step in x, a step in y (θ), half a step
   in x, as a program of three launches.
   - [x] P: `strang-run`: k runs are `strangRun`; `strang-total`, `strang-nonneg`.
   - [x] T: an 8 × 5 grid, 2 runs, in `grid.py`.
   - [ ] 3b. Advection in k with its own Courant numbers. Open.
4. Fused reductions (from M2): each sum in a loop over the lanes, then every lane, in one launch.
   - [x] P: `dsFusedK-sound`: `ds_fused` is `OceanWaves.Sources.dsRate`, its three sums
     included, by `refl`; `breakScaleK-sound` and `breakScaleK-le` for `break_scale`.
   - [x] T: 20 lanes each. The sums run in float32 in Triton's order, inside the budget.

## M4: WW3's own source terms

This is where the specification changes from the reduced physics to WW3's. For each routine:
read `model/src/<file>.F90` at a pinned WW3 commit, transcribe it into Agda under `--safe`,
cite file and line, then write the kernel and its proof as in M0.

The pin: metocean/WW3, tag `7.14.mos-92e2cf6`, commit `92e2cf66af6e15ae80eb12562f2b05d4a2d75df5`.
Each module's header lists the lines it transcribes.

Order (most of a WW3 step's run time first, to be measured with a profile at the pin):

1. `W3SNL1`, the DIA (`OceanTriton.W3SNL1`, from `w3snl1md.F90:335-414`): UE on the extended
   grid with its zero rows and its tail (`FACHFE`), the eight arrays SA1 … DA2M at every
   position, then S and D by the IC tables; eleven launches in the order of the Fortran's loops.
   CONS (`:324-326`, it needs `EXP`) and INSNL1's tables (`:467-770`) are data.
   - [x] P: `snl1-S`, `snl1-D`: the program's S and D are the routine's at every point, for
     every input and every table. The tail is a `rep` whose count is at most the number of tail
     rows (`ue-closed`).
   - [x] T: NTH = 4, NFR = 3, two tail rows, 24 positions, 12 points, synthetic tables in range.
   - [ ] T with INSNL1's own tables, and the action and energy properties of the quartets
     (`WaveTheory.Quadruplets`) restated for this form. Open.
2. [ ] `W3SIN4` and `W3SDS4` (ST4 input and dissipation). Open: they need `exp`, `log`, `tanh`
   and `sqrt` (below).
3. [ ] `W3SRCE`'s integration: the dynamic time step and the limiter as WW3 writes them, with
   the sub-steps of `WaveTheory.Splitting`. Open.
4. Bottom friction and depth-induced breaking.
   - [x] `W3SBT1` (`OceanTriton.W3SBT1`, from `w3sbt1md.F90:175-212`), the JONSWAP form, with
     the deep-water test and the loop's `EXIT` written as they are. P: `sbtD-sound`,
     `sbtS-sound`: the kernel is the routine at every spectral point when WN increases over the
     bins (every WW3 frequency grid) and the depth is not negative; the loop needs no lane of
     its own. T: 12 bins of 3 directions, k d on both sides of 6.
   - [ ] Depth-induced breaking as WW3 writes it (`W3SDB1`). Open; `break_cap` and
     `break_scale` are the reduced form.

The obstacle: ℚ has no `exp`, `log`, `tanh`, `sqrt` or `cos`, and ST4 uses all of them. Two
ways, decided per function:

- **A function model**, as `TanhModel` does for tanh: the Agda states the properties the proofs
  need, the theorems hold for every function with them, and the printer emits `tl.exp` and its
  kin. P then covers the arithmetic around the function, not the function's own bits.
- **A rational approximant** with a proved error bound, as `padeT` is for tanh. P covers it
  exactly, and the bound is the gap to the true function.

Checkpoint per routine: the Agda statement cites `model/src/<file>.F90:<line>` at the pin, and a
second reader compares the two. That comparison is by eye, so it is recorded as such.

## M5: verification against WW3 (the W mark)

A routine gets W only through numbers from a running WW3:

1. Build WW3 at the pinned tag with the switch of a regression test, unchanged.
2. Capture each routine's inputs and outputs from that run, at the routine's entry and exit
   (a debugger script or a temporary print outside the build that is compared).
3. Replay the captures through the Triton kernels and compare. The tolerance is float32
   rounding and is written down before the first run; a difference is a defect of the Agda or
   of the kernel until two runs of the Fortran itself differ.
4. Then the whole step: a regression test of WW3 (for example the 1-D propagation tests
   `ww3_tp1.x`) run by the chained kernels of M2 and compared field by field.

Checkpoints: one W row per routine in the status table, with the capture and the command that
replays it.

Done in this change ([`ww3-replay/`](../ww3-replay/README.md), `just ww3-replay`):

- [x] 1. `nix/ww3-replay.nix` builds WW3 at the pin with its own CMake, unchanged, with the switch
  of `ww3_ts1` (`ST4 NL1 BT1 DB1`).
- [x] 2. `ww3_capture.F90` links that build's library and calls W3SNL1, W3SBT1 and W3SDB1 as
  W3SRCE does, on the spectrum of a restart that `ww3_shel` wrote, with INSNL1's own tables.
  Three cases of `ww3_ts1`: 2500 m (the test as it is), 6 m, and 2 m with breaking. Nothing in WW3
  is changed or printed from inside; the run reproduces the captures byte for byte.
- [x] 3. W: the printed Triton kernels give W3SNL1's S and D (eleven launches) and W3SBT1's S
  and D **bit for bit**, 864 values each, on all three captures (Triton's CPU interpreter). The
  budget was written before the first run; no value needed it.
- [ ] W3SDB1: captured (the surf case breaks), not replayed, since no kernel exists for it yet.
- [ ] 4. The whole step against a regression test. Open: it needs ST4 and W3SRCE.

## M6: GPU runs and timing

- Checkpoint T on a GPU: `just ocean-triton-cuda` on a CUDA device, the same comparison.
- Timing only after W on the same commit: the machine, the command, the median of three runs.
- The float32 kernels against the float64 parts of WW3: where WW3 uses double precision, the
  kernel keeps it (`tl.float64`), and `Emit` takes the kind from the Agda.

## What stays trusted at every milestone

- The printers `agda/src/OceanTriton/Emit.agda`, `EmitGrid.agda` and `EmitGather.agda`: no
  Triton semantics exists in Agda. `rep` prints a loop of R steps, which means `repN` only where
  the count is at most R; `check_gather.py` checks that bound on every launch (`REP_BOUNDS`).
- Triton and the GPU's arithmetic: float32 rounding, the order of a reduction, the compiler's
  contraction of a multiply and an add.
- For M4 and M5: the reading of the Fortran into Agda, until the replay of M5 checks it.

## Commands

```bash
bash checks/agda.sh          # P: every theorem of agda/src, OceanTriton included
just ocean-triton            # T: the printed kernels against the exact values
just ocean-triton-write      # print the six files of ocean-triton/ again
just ocean-triton-cuda       # T on a CUDA GPU
```
