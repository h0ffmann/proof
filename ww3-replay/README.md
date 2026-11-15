# WAVEWATCH III, run and replayed through the Triton kernels

Milestone M5 of [`ocean-triton/PLAN.md`](../ocean-triton/PLAN.md): the W mark. A kernel printed
from Agda gets it only through numbers from a running WAVEWATCH III (WW3), not through a
transcription read by eye. This folder builds WW3, runs one of its regression tests, captures
the source-term routines and their tables from the run, and replays the captures through the
kernels of [`ocean-triton/gather.py`](../ocean-triton/gather.py), [`ocean-triton/sdb.py`](../ocean-triton/sdb.py)
and [`ocean-triton/lanes.py`](../ocean-triton/lanes.py).

## The result

| Routine | Captured | Replayed by | S | D |
|---|---|---|---|---|
| W3SNL1, the DIA (`w3snl1md.F90:335-414`) | 3 cases, with INSNL1's own tables | the program `w3snl1`, 11 launches | 864 of 864 values bit for bit, in each case | 864 of 864 bit for bit |
| W3SBT1, JONSWAP bottom friction (`w3sbt1md.F90:175-212`) | 3 cases | `w3sbt1_s`, `w3sbt1_d` | 864 of 864 bit for bit | 864 of 864 bit for bit |
| W3SDB1, depth-induced breaking (`w3sdb1md.F90:223-280`) | 3 cases (it breaks in `surf`) | `w3sdb1_fdonly` of [`sdb.py`](../ocean-triton/sdb.py), CBJ in float64 | 864 of 864 bit for bit | 864 of 864 bit for bit |
| W3SDS4, ST4 dissipation (`w3src4md.F90:1872-2599`) | 3 cases | the lane program `w3sds4`, 7 launches | 864 of 864 bit for bit | 864 of 864 bit for bit |
| W3SIN4, ST4 wind input (`w3src4md.F90:424-906`) | 3 cases | `w3sin4`, 7 launches | 864 of 864 bit for bit; LLWS 864 of 864; TAUWX, TAUWY, TAUWNX, TAUWNY 4 of 4 | 864 of 864 bit for bit |
| W3SLN1, linear input (`w3sln1md.F90:176-199`) | 3 cases | `w3sln1` | 864 of 864 bit for bit | — |

| Routine | Captured | Replayed by | Outputs |
|---|---|---|---|
| W3SPR4 with CALC_USTAR (`w3src4md.F90:143-385`, `:1738-1840`) | 3 cases | `w3spr4`, 3 launches | EMEAN, FMEAN, FMEAN1, WNMEAN, AMAX, USTAR, Z0, CHARN, CD, FMEANWS, DLWMEAN: 11 of 11 bit for bit |
| WAVNU1 from DISTAB's tables (`w3dispmd.F90:84-201`) | 3 cases | `wavnu1`, 2 launches | K 36 of 36, CG 36 of 36 bit for bit |
| TABU_STRESS (`w3src4md.F90:1188-1309`) | `deep` (the tables depend on the grid only) | `tabu_stress` | TAUT 40401 of 40401 bit for bit |
| TABU_TAUHF (`w3src4md.F90:1325-1477`) | `deep`, a call that `ww3_capture` makes itself | `tabu_tauhf` | TAUHFT 20301 of 20301 bit for bit |
| TABU_TAUHF2 (`w3src4md.F90:1495-1720`) | `deep` | `tabu_tauhf2`, 2 launches | TAUHFT 20301 of 20301 bit for bit; TAUHFT2, plane 1: 20301 of 20301 bit for bit |
| INSIN4's direction and cumulative tables (`w3src4md.F90:1032-1048`, `:1144-1172`) | `deep` | `insin4`, 3 launches | SATINDICES 552 of 552, SATWEIGHTS 552 of 552, CUMULW 746496 of 746496 bit for bit |
| W3SRCE, one call (`w3srcemd.F90:1207-1986`, `:1999-2067`) | `deep`, DTG = 60 s | [`srce.py`](srce.py): every kernel above, chained pass by pass | SPEC 864 of 864 and its 21 scalars bit for bit, two passes of 30 s (2462 s) |

The run is Triton's CPU interpreter, which computes in float32 with NumPy. The budget,
`|triton - ww3| ≤ 1e-6 max|ww3| + 1e-5 |ww3|`, was written in `replay.py` before the first run;
no value needed it. This is a measurement on three inputs of one test, not a proof for every
input. The proof is the other half: `snl1-S`, `snl1-D`, `sbtS-sound`, `sbtD-sound`, `sdb-cbj`,
`sdb-D` and `sdb-S` in
`agda/src/OceanTriton/` (and the theorems that each module's header names) say that the kernels
compute the transcription for every input.

TABU_TAUHF's own table is not what W3SIN4 reads in this test: ww3_ts1 has TTAUWSHELTER = 0.3,
so INSIN4 calls TABU_TAUHF2 after it (`w3src4md.F90:1021-1026`), which writes TAUHFT again with
another ZZ0. The replay compares `tabu_tauhf2` with the TAUHFT that W3SIN4 reads, and
`tabu_tauhf` with a call of TABU_TAUHF that `ww3_capture` makes after every other capture.

## The pieces

- [`nix/ww3-replay.nix`](../nix/ww3-replay.nix) is the shell `nix develop .#ww3-replay`. It
  fetches WW3 from MetOcean's fork at tag `7.14.mos-92e2cf6`, commit
  `92e2cf66af6e15ae80eb12562f2b05d4a2d75df5` (the pin of `ocean-triton/PLAN.md`). It builds WW3
  with WW3's own CMake (`Release`), unchanged, with the switch of the regression test `ww3_ts1`
  (`ST4 NL1 BT1 DB1`; the build stops if the switch file moves at the pin). gfortran, CMake and
  NetCDF come from `flake.lock`'s nixpkgs.
- [`ww3_capture.F90`](ww3_capture.F90) links that build's `libww3.a`. It reads `mod_def.ww3`
  as `ww3_uprstr` does, and W3IOGR then calls INSNL1, so the DIA's tables are WW3's own. It
  reads the spectrum of a restart that `ww3_shel` wrote. Then it calls the source terms as
  W3SRCE calls them, with the means of W3SPR4 and the wavenumbers of WAVNU1, then W3SRCE itself
  as W3WAVE calls it (`w3wavemd.F90:2224`), with DTG = 60 s. It writes every input and output
  with nine significant digits, which read back to the same float32, and the constants and
  tables of `mod_def.ww3` that the kernels take as inputs. Nothing inside WW3 is changed or
  printed.
- [`run.sh`](run.sh) runs `ww3_grid`, `ww3_strt` and `ww3_shel` on the test's own input, with
  one restart written at 06:00 of the first day (the test writes none), in three cases:

  | Case | Change to the test's input | What it reaches |
  |---|---|---|
  | `deep` | none: 2500 m | W3SBT1 and W3SDB1 give zero |
  | `shallow` | depth scale -6 instead of -2500: 6 m | W3SBT1 on part of the spectrum, both branches of `k d > 6` |
  | `surf` | depth scale -2, minimum depth 1 m instead of 5.75 | W3SDB1 breaks (`LBREAK` true) |

- [`captures.sha256`](captures.sha256) holds the sha256 of the three captures, not the captures
  (1,911,558 lines each, most of them TAUHFT2 and CUMULW). The check runs WW3 again, writes fresh captures, requires these hashes,
  and replays the fresh files. To keep the captures, run `ww3-replay/run.sh OUTDIR`.
- [`replay.py`](replay.py) turns WW3's tables into the 0-based positions of the Agda modules
  and runs the printed launches. This translation of indices is its only part that is not
  printed from Agda. `--only` picks routines, `--tables` adds INSIN4's tables, `--srce` a whole
  W3SRCE call.
- [`srce.py`](srce.py) runs W3SRCE's integration loop on the kernels: the host decides how many
  passes and when the loop ends, and computes W3SNL1's CONS with glibc's `expf`, as W3SRCE does
  between the calls; DT, the limiter, the new spectrum, the tail and the fluxes come from the
  kernels.

## Run it

```bash
just ww3-replay          # checks/ww3-replay.sh: WW3 builds, its captures have the committed hashes, the replay is bit for bit, self-test
just ww3-replay-write    # run WW3 again and write the captures' hashes into captures.sha256
ww3-replay/run.sh DIR    # run WW3 and write the three captures into DIR, to read or replay them
```

After a change that moves the captures on purpose (the pin, the switch, a case of `run.sh`, or
`ww3_capture.F90`), run `just ww3-replay-write`, then `just ww3-replay`, and commit the new
`captures.sha256` with the change.

The self-test prints one `+` of the S kernel of W3SNL1 as `-`, drops the sign of W3SDB1's D,
calls glibc's scalar `powf` where W3SDS4's code calls libmvec's, raises COSWIND to SSINTHP+1 in
W3SIN4, prints TABU_STRESS's XM+1 as 1.25 and INSIN4's 0.5*C2 as 0.25*C2, and changes one
captured output of W3SNL1, W3SDB1, W3SDS4 and W3SIN4 by a part in 1000. Each change must fail
the replay. W3SRCE's call is not mutated here, since each replay of it takes about an hour; the
mutations of `checks/ocean-triton.sh` reach its kernels.

The CPU interpreter is slow: a launch runs as one block of up to 65536 lanes
(`ocean-triton/check_lanes.py`), and still the W3SRCE call takes about an hour and TAUHFT2's
plane about 12 minutes on one core; the check runs the tables and W3SRCE on `deep` only.

## What is not checked

- **One test, one point, one time.** The captures are three states of `ww3_ts1`, a one-point
  test without propagation. Other switches, grids and states are not replayed. W3SRCE is
  replayed on one capture, with one step DTG.
- **TAUHFT2 in part.** One plane of 51 is replayed (the plane I folds over the I planes below
  it, so a plane costs I + 2 sums over JTOT); `ww3-replay/replay.py --plane I` takes another.
  A C program that follows the routine's GIMPLE gave all 1035351 entries bit for bit once, by
  hand; it is not part of the check.
- **The compiler of the reference.** WW3 is built by gfortran 16.2 at `-O3`
  (CMake's `Release`) on x86-64. Another compiler or flag can change WW3's own bits. The
  replay compares with this build only.
- **Not on a GPU.** `--device cuda` exists and has not run. A GPU's float32 arithmetic may
  contract a multiply and an add, which the CPU interpreter does not do.
- **W3SDB1's other branches.** Only `surf` breaks, with B ≈ 0.24: the fixed-point loop runs, but
  B > 0.5, BB ≥ 1 and FDONLY false (ww3_ts1 sets FDONLY true, so TANH is not called) are not
  reached here. `ocean-triton/check_sdb.py` covers them against Agda's Float, not against WW3.
- **The functions.** W3SDB1's kernel computes EXP and DSQRT with NumPy's float64, and WW3 with
  glibc's and the CPU's; they agree on these inputs. The lane programs call glibc's float32
  functions and libmvec's `powf` as written in Triton in `ocean-triton/libm.py`, which its own
  self-test checks against the libraries. A GPU's `exp` may not agree.
