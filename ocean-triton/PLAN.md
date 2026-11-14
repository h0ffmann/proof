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
| M2 Space: 2-D propagation and the time loop | done in this change, except step 4 | 2 programs (5 kernels) | 2 programs (CPU interpreter) | 0 |
| M3 Spectral space and other grids | planned | 0 | 0 | 0 |
| M4 WW3's own source terms | planned | 0 | 0 | 0 |
| M5 Verification against WW3 | planned | — | — | 0 |
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

## M2: space (done in this change, except step 4)

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
4. [ ] T: the fused whitecapping (the three reductions, then `ds_rate`) in one launch with a
   block reduction, compared with the three-launch form. Not done; it moves to M3.

## M3: spectral space and other grids

1. Refraction and shoaling: `WaveTheory.Refraction` (Snell, k sin θ kept) and
   `WaveTheory.Shoaling` (energy flux kept, depth-limited breaking `breakCap`, `breakScale`).
   Checkpoints P and T per kernel; WW3 turns refraction into advection in θ (its `W3KTP` routines, not yet read at a pin), so step 3
   below adds that form.
2. Unstructured grids (`WaveTheory.Unstructured`): a step on a triangle mesh as a gather over
   each node's incoming edges, from a compressed edge list sorted by target node. A gather keeps
   the order of the sum fixed; a scatter with atomics would not.
   - Checkpoint P: the gather equals `meshStep` for every mesh; `meshStep-total` restated.
   - Checkpoint T: the two-triangle mesh of `WaveTheory.GridExamples`, then a mesh of
     `triangle-grids/`.
3. Advection in θ and k with their own Courant numbers, from `WaveTheory.Splitting` (Lie and
   Strang orders).
4. From M2: the fused whitecapping (the three reductions, then `ds_rate`) in one launch with a
   block reduction. Checkpoint T: compared with the three-launch form.

## M4: WW3's own source terms

This is where the specification changes from the reduced physics to WW3's. For each routine:
read `model/src/<file>.F90` at a pinned WW3 commit, transcribe it into Agda under `--safe`,
cite file and line, then write the kernel and its proof as in M0.

Order (most of a WW3 step's run time first, to be measured with a profile at the pin):

1. `W3SNL1`, the DIA: the quartets of `WaveTheory.Quadruplets` and the off-grid weights of
   `WaveTheory.Interpolation`, on WW3's geometric frequency grid
   (`WaveTheory.SpectralGrid`). Checkpoint P: action kept (`apply-action`) for the printed
   kernel; energy kept only on resonant quartets.
2. `W3SIN4` and `W3SDS4` (ST4 input and dissipation).
3. `W3SRCE`'s integration: the dynamic time step and the limiter as WW3 writes them, with the
   sub-steps of `WaveTheory.Splitting`.
4. Depth-induced breaking and bottom friction, as `Shoaling` and new modules.

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

## M6: GPU runs and timing

- Checkpoint T on a GPU: `just ocean-triton-cuda` on a CUDA device, the same comparison.
- Timing only after W on the same commit: the machine, the command, the median of three runs.
- The float32 kernels against the float64 parts of WW3: where WW3 uses double precision, the
  kernel keeps it (`tl.float64`), and `Emit` takes the kind from the Agda.

## What stays trusted at every milestone

- The printer `agda/src/OceanTriton/Emit.agda`: no Triton semantics exists in Agda.
- Triton and the GPU's arithmetic: float32 rounding, the order of a reduction, the compiler's
  contraction of a multiply and an add.
- For M4 and M5: the reading of the Fortran into Agda, until the replay of M5 checks it.

## Commands

```bash
bash checks/agda.sh          # P: every theorem of agda/src, OceanTriton included
just ocean-triton            # T: the printed kernels against the exact values
just ocean-triton-write      # print kernels.py and vectors.json again
just ocean-triton-cuda       # T on a CUDA GPU
```
