# port-audit: Z3 checks of chaceon

[chaceon](https://github.com/h0ffmann/chaceon) ports WAVEWATCH III (WW3) from Fortran to Rust for the
GPU. It checks the port by `cmp` on whole runs and by captured calls: the Rust and the Fortran give
the same bits on the inputs that ran. That evidence says nothing about an input that did not run,
and it cannot see a defect that both sides share. `Chaceon.scala` states facts about chaceon's code for
every input and asks Z3 for a counterexample, in the style of the rest of `z3-scala/`: `unsat`
means none exists. The code is `z3-scala/src/main/scala/portaudit/` (`Chaceon.scala`,
`Coverage.scala`); this folder holds its report.

The audited commit is `fe531e1e64950c0f3ce7987ae4ed0325a56adfbe` (2026-11-04). Every `file:line`
below is a path in chaceon at that commit.

The same checks also run in Haskell, `tools/port-audit/` (Z3 through SBV, `bash
checks/port-audit-haskell.sh`): the 28 statements give the same verdicts, and the coverage table
it writes is the one below, byte for byte. The Scala stays until it is removed.

```sh
tools/port-audit/run.sh chaceon            # the 28 statements, about 13 s
tools/port-audit/run.sh coverage --check   # the coverage table below is current, about 10 s
z3-scala/z3.sh chaceon     # 28 lines of OK, about 10 s; exit code 1 if one fails
z3-scala/z3.sh coverage    # how much of WW3 is translated and integrated (below)
just port-audit            # the same; `just check` runs it too (checks/port-audit.sh)
```

## What Z3 checks

| Check | chaceon code | Statement | Theory |
|---|---|---|---|
| `no_tie`, `margin` (t = 24, 25) | `rust/tools/spirv_exact/src/main.rs:3-7, 57-64` | a quotient `A/B` of two 24-bit significands is never a midpoint `M/2^t` of the `f32` grid, and stays `m/2^49` away from it | bit-vectors |
| `same_side`, `same_side_not_tie` | same | an `f64` quotient within `5/2 * 2^-52` (Vulkan's 2.5 ULP) is on the same side of every midpoint as the exact one | reals |
| `closer_lo` | same | round to nearest between two grid points is the comparison with their midpoint | reals |
| `nint = round half away` | `rust/crates/ww3-kernels/src/util.rs:21-31` | `nint` is gfortran's `NINT` (ties away from zero) for every `f32` in `(-2^31, 2^31)`, and its `x - t` is exact | IEEE `f32` |
| `floor = round down` | `util.rs:34-37` | `floor` rounds toward minus infinity for every `f32` in range | IEEE `f32` |
| `sign = SIGN(A, B)`, `sign_negative_zero` | `util.rs:41-43` | the bit copy is Fortran's `SIGN`, and `SIGN(a, -0.)` is `-|a|`, as gfortran gives | IEEE `f32` |
| `spectrum_nonneg` | `rust/crates/ww3-kernels/src/srce.rs:619, 624, 629, 742` | `(sp + einc).max(0.)` is never negative and never NaN, for every `f32` input, NaN and infinity included | IEEE `f32` |
| `limited_step_le_dam`, `limited_step_sign` | `srce.rs:617-618` | the limited increment is at most `dam` and keeps the sign of the unlimited one | IEEE `f32` |
| `tail_no_negative_zero` | `srce.rs:671-675` | the `+ 0.` in the high-frequency tail turns a `-0` into `+0` | IEEE `f32` |
| `implicit_le_explicit` | `srce.rs:617, 623, 628` | the semi-implicit increment is never larger than the explicit one, for any sign of `vd` | reals |
| `limiter_bounds_increment` | `srce.rs:598-600` | with `vd <= 0` and without the `1e-10` clamps, the limited `dt` keeps each increment within `damax` | reals |
| `split_idt_ge_1`, `split_le_rem`, `split_le_dt/0.99` | `srce.rs:604-605` | the remaining time splits into `idt >= 1` equal parts, each at most the remaining time and at most `dt / 0.99` | reals, integers |
| `step_never_past_dtg`, `step_progress` | `srce.rs:607-612` | a pass never moves `dttot` past `dtg` and moves it by at least `min(dtmin, dtg - dttot)` | reals |

Five checks expect a counterexample. Each one shows a hypothesis that is needed or a gap between a
comment and the code:

| Check | What the counterexample shows |
|---|---|
| `margin_2^48_fails` | the margin `2^-49` cannot be doubled (chaceon's Lean log reports the same) |
| `no_tie_needs_normal` | a subnormal quotient can be a midpoint exactly, so `spirv_exact` needs the normal range (`main.rs:7`) |
| `same_side_8ulp_fails` | an error of `8 * 2^-52` reaches the margin: the device must stay well under that |
| `limiter_vs_floor_0.5` | **`srce.rs:602`, `dt = dt.max(0.5)`, overrides the limiter**: when the limited step is under half a second, the increment exceeds `damax` |
| `split_le_dt` | **`srce.rs:604-605`: the factor `0.99` lets each equal part exceed the limited step**, by a factor up to `1/0.99` |

The last two are not defects of the port: the port is byte-identical to WW3 on every regtest, so the
Fortran very likely has the same lines (`W3SRCE` in `w3srcemd.F90`; not opened here). They say that
`damax` is a target for the step, not a bound on it.

## What Z3 cannot prove here

- **That the Rust equals the Fortran.** No formal semantics of Fortran or of gfortran `-O3` exists to
  state it against; chaceon's `cmp` and captures are the evidence (`docs/LEAN_202610.md`, "Lean and
  Fortran").
- **The division rewrite on IEEE bits, end to end.** The direct statement, `f32(f64(a) / f64(b)) ==
  a / b` over Z3's floating-point theory, did not finish in 8 minutes, even with `a, b` in
  `[1, 2)`, and was stopped: Z3 bit-blasts a 53-bit divider. The check goes through the significands (`no_tie`, `margin`) and
  the reals (`same_side`), as chaceon's Lean proof does. That needs the scaling step: a power of two
  is exact in the normal range, so only `t = 24` and `t = 25` remain (`Chaceon.scala`, group D).
- **The device.** That `OpFConvert` rounds to nearest, that a device meets 2.5 ULP in `OpFDiv`, and
  that it honours `NoContraction` (`spirv_exact/src/main.rs:2-7`) are facts about a driver, not
  about code.
- **Overflow, zero, infinity and NaN operands of the division** (`main.rs:7-8`). They are outside the
  premises, as in Lean.
- **The source terms themselves** (`sin4.rs`, `sds4.rs`, `snl1.rs` and the others). Their values
  come from `logf`, `tanhf`, `expf` and powers in `ww3-libm` (`rust/crates/ww3-libm/src/lib.rs`).
  Z3 has no theory of these functions. The limiter is checked for any source values instead.
- **The limiter in `f32`.** `limiter_bounds_increment`, `split_*` and `step_*` hold over the reals.
  `srce.rs:593-607` computes in `f32`, with rounding in each sum and product; the checks do not
  cover that rounding.
- **The `1e-10` clamps** (`srce.rs:599-600`). The limiter is checked without them; with `vs` near
  zero or `1 + afac * vd <= 0` the clamp sets the step, and no bound on the increment follows.
- **The whole `W3SRCE` loop** (`srce.rs:546-684`). Z3 has no induction. `step_progress` shows that
  each pass moves forward by `min(dtmin, rem)`, so the loop ends when `dtmin > 0`; the loop itself
  and the `0.9999 * dtg` exit (`srce.rs:681`) are not modelled.
- **`pow5` as GCC's power tree** (`util.rs:63-68`). The tree is the right one only if it is the one
  gfortran `-O3` emits; that is a fact about the compiler.
- **`x as i32` outside `(-2^31, 2^31)`**: Rust saturates, gfortran does not define `NINT` there. The
  `nint` and `floor` checks assume the range.

## Coverage: translated and integrated

`Coverage.scala` measures how much of WW3 chaceon has translated, and how much of that its switch files
compile. The unit is a Fortran code line of `model/src/*.F90` at chaceon's WW3 pin: not blank, not a
`!` comment, not a preprocessor line, as in chaceon's `scripts/port_summary.py` (the totals agree:
120,705).

- **Translated**: a line inside a routine that chaceon's `rust/ports.tsv` lists, so Rust exists for it.
  Each row's status is its evidence, weakest first: `translated`, `routine` (every captured call
  bit-identical), `host` and `spirv` (whole output files byte-identical).
- **Integrated**: a translated line that the port's target build, `switches/switch_chaceon_shrd`,
  compiles. A routine's range also holds the code of other switches (`#ifdef W3_MPI`, `W3_T` test
  prints, other physics), so a translated line can be one the target never compiles.

Z3 reads the switches. WW3 picks code in two ways, and both become formulas over one Boolean per
switch: the CMake rules choose the files (`model/src/cmake/switches.json` gives each switch its
`build_files`; `src_list.cmake` and `CMakeLists.txt` list the rest), and `#ifdef`, `#ifndef`, `#if`,
`#elif`, `#else` choose the lines. A switch file compiles a line when the switch set implies the
line's condition (refutation: `unsat`). Z3 also checks each switch file against the rules of
`check_switches.cmake` (one option per "one" category, at most one or two per "upto" category, no
`conflicts`, every `requires`), and calls a line dead when no switch set that the rules accept
compiles it. Macros that are not switches (`TEST_*`, `ENABLE_*`, `COAMPS`...) are off, as in a build
with no `-D` flag, and NetCDF is found, as in chaceon's build.

```sh
z3-scala/z3.sh coverage           # fetch both pins into port-audit/.cache (13 MB), print, ~25 s
z3-scala/z3.sh coverage --write   # rewrite the block below
z3-scala/z3.sh coverage --check   # exit 1 when the block is stale (checks/port-audit.sh runs it)
```

What it cannot tell: whether a compiled line runs in a given run (a compiled branch can be dead at
run time; chaceon's captures and `cmp` answer that), and whether the Rust of a translated line is
right. A row of `rust/ports.tsv` that names a whole file counts the whole file.

One finding about WW3 itself: `STAB3` can never be built. `switches.json` gives it `"requires":
["ST3", "ST4"]`, and `check_switches.cmake` reads each string of `requires` as a switch that must be
on (only a nested array means "one of"), while the source-term category allows exactly one `ST`
option. The intent looks like `[["ST3", "ST4"]]`; this is not reported to WW3.

<!-- coverage:begin -->

Generated by `z3-scala/z3.sh coverage --write` from chaceon `fe531e1e` (`rust/ports.tsv`, `switches/`) and WW3 `92e2cf66` (`model/src/*.F90`, 135 files, and its CMake rules). Unit: Fortran code lines.

| WW3 code lines | Lines | Share |
|---|---:|---:|
| All of `model/src/*.F90` | 120,705 | 100% |
| **Translated**: in a routine of `rust/ports.tsv` | 45,104 | 37% |
| Compiled by `switch_chaceon_shrd`, the port's target build | 72,642 | 60% |
| **Integrated**: translated and compiled by `switch_chaceon_shrd` | 34,304 | 47% of the target build |
| Translated, compiled only by a capture switch file | 2,993 | 7% of translated |
| Translated, compiled by no chaceon switch file | 7,807 | 17% of translated |
| Dead: no switch set that WW3's rules accept compiles it (Z3 `unsat`) | 4,330 | 4% |

| Evidence in `rust/ports.tsv` | Translated | Integrated in the target | In some chaceon switch file |
|---|---:|---:|---:|
| `spirv` | 3,391 | 2,180 | 2,355 |
| `host` | 26,135 | 20,683 | 21,642 |
| `routine` | 2,334 | 561 | 1,966 |
| `translated` | 13,244 | 10,880 | 11,334 |

| Switch file | WW3's rules (Z3) | Compiles | Of it translated |
|---|---|---:|---:|
| `switch_chaceon_bt4` | accepted | 72,959 | 34,571 (47%) |
| `switch_chaceon_ice1` | accepted | 72,743 | 34,390 (47%) |
| `switch_chaceon_shrd` | accepted | 72,642 | 34,304 (47%) |
| `switch_chaceon_st1` | accepted | 71,212 | 32,993 (46%) |
| `switch_chaceon_st2` | accepted | 71,576 | 33,311 (47%) |
| `switch_chaceon_st2flx3` | accepted | 71,610 | 33,339 (47%) |
| `switch_chaceon_st3` | accepted | 71,654 | 33,385 (47%) |
| `switch_chaceon_st6` | accepted | 71,684 | 33,404 (47%) |
| `switch_metocean_st4` | accepted | 77,231 | 34,994 (45%) |

Translated lines that are dead: 104. Switch options that no accepted switch set can turn on: `STAB3`.

<!-- coverage:end -->
