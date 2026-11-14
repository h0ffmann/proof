# Ocean-wave kernels as Triton GPU kernels, printed from Agda

The question: can the Agda formalization of the ocean-wave kernels (`agda/src/OceanWaves/`) give
the code of GPU kernels in [Triton](https://triton-lang.org)? Yes, for the kernels of one model
step, with one part that is trusted and one difference that no proof covers. This folder holds
the result.

## The answer, in short

Agda's own backends (GHC, JavaScript) compile a whole Agda program. They do not give a Triton
kernel, and `ℚ` in `OceanWaves` is exact arithmetic on unbounded integers, which a GPU does not
have. So the kernels go through a small language instead:

1. `agda/src/OceanTriton/Expr.agda` defines `Expr`, the expressions of a kernel: array reads at
   lane `i + k`, the upwind read (`upstream`), scalars, constants, `+ - *`, negation, the total
   division `/₀`, `⊔`, `⊓`, a choice on `x ≤ y` or `x < y`, and a read of a neighbour bin gated
   to the interior. `eval` gives each expression its exact meaning over `ℚ`. A `map` kernel
   writes one value per lane; a `reduce` kernel writes the sum over the lanes, as `sumTo` does;
   a loop kernel keeps two registers per lane for a fixed number of steps.
2. `agda/src/OceanTriton/Kernels.agda` and `Step.agda` write 18 kernels in `Expr` and prove,
   for every input, that the meaning of each one is the `OceanWaves` or `WaveTheory` kernel. Most proofs are
   `refl`; the stencil of S_nl and the bisection loop are proved by sums and by induction. So the
   theorems of `OceanWaves` hold for the meaning of the printed code; positivity of the upwind
   step, of the wind input and of the source step are restated there.
3. `agda/src/OceanTriton/Emit.agda` prints each kernel as a `@triton.jit` function.
4. `agda/src/OceanTriton/Vectors.agda` computes exact outputs on test inputs with `runMap` and
   `runReduce`, the same terms the theorems are about.
5. `tools/ocean-triton/` compiles a small program with Agda's GHC backend that writes
   [`kernels.py`](kernels.py) and [`vectors.json`](vectors.json), and the launch programs
   described below.
6. [`check.py`](check.py) runs the Triton kernels and compares each output with the exact value.

Every file in `agda/src/OceanTriton/` is `--safe`. `tools/ocean-triton/Main.agda` only writes
the two files, the same exception as `tools/prose-check/Main.agda`.

## The kernels

| Triton kernel | Shape | `OceanWaves` kernel | Theorem |
|---|---|---|---|
| `advect` | map | `Advection.advect` (upwind, flux form) | `advectK-sound`, `advectK-nonneg` |
| `advect_cg` | map | `advect` with `μ = c_g Δt / Δx` | `advectCgK-sound`, `advectCgK-euler` |
| `sigma2` | map | `Dispersion.sigma2` with the Padé tanh | `sigma2K-sound` |
| `group_speed` | map | `Dispersion.groupSpeed` with the Padé tanh | `groupSpeedK-sound` |
| `wind_rate` | map | `Sources.windRate` | `windK-sound`, `windK-nonneg` |
| `energy_total` | reduce | `Sources.Etot` | `etotK-sound` |
| `energy_over_sigma`, `energy_over_k` | reduce | the sums under `σMean` and `kMean` | through `dsK-sound` |
| `ds_rate` | map | `Sources.dsRate`, with the three sums as scalars | `dsK-sound` |
| `lin_step` | map | `Sources.linStep` | `linStepK-sound` |
| `euler_step` | map | `Sources.eulerStep` | `eulerK-sound` |
| `source_step` | map | `Sources.sourceStep` (limiter included) | `sourceK-sound`, `sourceK-nonneg` |
| `snl` | map | `Sources.snl` (quadruplet transfer) as a three-point stencil | `snl-stencil`, `snlK-sound`, `snlK-conserves` |
| `source_step_snl` | map | `Sources.sourceStep` with S_nl computed in the kernel | `sourceSnlK-sound` |
| `wavenumber` | loop | `Bisection.waveNumber` (Padé tanh), for every number of steps | `wavenumberK-sound` |
| `sxx`, `sxy`, `syy` | map | `WaveTheory.RadiationStress` (the WW3 output fields SXX, SXY, SYY) | `sxxK-sound`, `sxyK-sound`, `syyK-sound`, `stressK-trace` |

`dsK-sound` states the whole whitecapping chain: the three reduce kernels, then `ds_rate`, give
`dsRate P S i` for every spectrum `S`.

## The programs: a time step as a chain of launches (milestone M2)

A host script that launches kernels cannot be proved. So the chain is written in Agda too.
`agda/src/OceanTriton/Grid.agda` has 2-D kernels: one lane per cell (x, y), with periodic reads
west and south, and the gated read along y. It also has `Program`, a list of launches on named
buffers. Its meaning runs the launches in order (`steps`), and `repeat` runs the program k
times. `agda/src/OceanTriton/Space.agda` writes two programs and proves them:

| Program | Launches | Its meaning is | Theorems |
|---|---|---|---|
| `prop2d` | `sweep_x` (F to T), `sweep_y` (T to F) | `WaveTheory.Propagation2D.run2D`, for every k, as an equality of fields | `prop2D-step`, `prop2D-run`; `prop2D-total`, `prop2D-nonneg`, `prop2D-le` restated |
| `model` | `propagate` (N to P), `exchange` (P to D), `sources` (to N) | `OceanWaves.ActionBalance.step` at every cell and bin; k runs are `WaveTheory.TimeLoop.run` | `model-step`, `model-run`; `model-nonneg` restated |

The model program needs a `StepConfig` whose source rates a kernel can read as data: the wind
input and the dissipation per bin, and the exchange amount κ N (`ModelConfig`). The general
`StepConfig` takes functions of the local spectrum.

`agda/src/OceanTriton/EmitGrid.agda` prints the 2-D kernels and a `PROGRAMS` table into
[`grid.py`](grid.py); `agda/src/OceanTriton/GridVectors.agda` computes the exact result of
each program with `repeat`, into [`grid_vectors.json`](grid_vectors.json). [`check_grid.py`](check_grid.py)
runs the launches in order, each into a fresh buffer, and compares every cell and the total.
`prop2d` runs 3 times on a 9 × 7 grid; `model` runs 2 times on 5 cells and 6 bins, with the
limiter clipping at both bounds.

## What is not proved

- **The printer.** No Triton semantics exists in Agda, so nothing proves that the printed Python
  means what `eval` means. `Emit.agda` and `EmitGrid.agda` are short and map each constructor to
  one Triton expression; their headers list them. The host loop of `check_grid.py`, which
  launches the `PROGRAMS` rows in order, is trusted the same way.
- **Floating point.** Triton computes in float32, `eval` in `ℚ` (AGENTS.md rule 7). `check.py`
  accepts an output when `|got - exact| ≤ 1e-6 + 1e-5 |exact|`. This is a rounding budget,
  measured, not proved. On the test inputs the worst kernel uses 3% of it.
- **The reduce kernels add in another order** than `sumTo`. The exact sum is the same; the
  rounded sum is not.
- **Not WAVEWATCH III's numbers.** The kernels are those of the reduced physics of
  `OceanWaves`, not WW3's routines. [`PLAN.md`](PLAN.md) has the milestones and checkpoints
  that lead to WW3, and what "verified against WW3" will mean.
- **The bisection in float32** takes the same branch as the exact one only when no midpoint is
  within rounding of the root's test. On the test inputs every branch is the same.
- **No GPU run here.** `just ocean-triton` runs Triton's interpreter on the CPU, which executes
  the same kernel source with NumPy. `just ocean-triton-cuda` runs on a CUDA device; it has not
  run yet.

## Run it

```bash
just ocean-triton          # checks/ocean-triton.sh: files current, 18 kernels and 2 programs agree, self-test
just ocean-triton-write    # print the four generated files again after a change to the Agda
just ocean-triton-cuda     # the same comparison on a CUDA GPU
```

`checks/ocean-triton.sh` enters `nix develop .#agda` for Agda (`nix/agda.nix`) and
`nix develop .#triton` for Triton 3.7.1, PyTorch 2.13.0 and NumPy (`nix/triton.nix`). Both
shells take every version from `flake.lock`. The self-test changes one exact value by 1/1000,
and one `+` to `-` in `advect`, then the same in a program's result and in `sweep_x`, and each
change must fail.

The test inputs reach both branches of every choice. `k h` is on both sides of 3 in the Padé
tanh, and the wind input is on and off. The limiter is active at both bounds and inactive. Lane 0
of `group_speed` has `k = 0`, a zero divisor, where `/₀` gives 0.
