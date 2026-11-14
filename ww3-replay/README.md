# WAVEWATCH III, run and replayed through the Triton kernels

Milestone M5 of [`ocean-triton/PLAN.md`](../ocean-triton/PLAN.md): the W mark. A kernel printed
from Agda gets it only through numbers from a running WAVEWATCH III (WW3), not through a
transcription read by eye. This folder builds WW3, runs one of its regression tests, captures
three source-term routines from the run, and replays the captures through the kernels of
[`ocean-triton/gather.py`](../ocean-triton/gather.py).

## The result

| Routine | Captured | Replayed by | S | D |
|---|---|---|---|---|
| W3SNL1, the DIA (`w3snl1md.F90:335-414`) | 3 cases, with INSNL1's own tables | the program `w3snl1`, 11 launches | 864 of 864 values bit for bit, in each case | 864 of 864 bit for bit |
| W3SBT1, JONSWAP bottom friction (`w3sbt1md.F90:175-212`) | 3 cases | `w3sbt1_s`, `w3sbt1_d` | 864 of 864 bit for bit | 864 of 864 bit for bit |
| W3SDB1, depth-induced breaking | 3 cases (it breaks in `surf`) | no kernel yet | — | — |

The run is Triton's CPU interpreter, which computes in float32 with NumPy. The budget,
`|triton - ww3| ≤ 1e-6 max|ww3| + 1e-5 |ww3|`, was written in `replay.py` before the first run;
no value needed it. This is a measurement on three inputs of one test, not a proof for every
input. The proof is the other half: `snl1-S`, `snl1-D`, `sbtS-sound` and `sbtD-sound` in
`agda/src/OceanTriton/` say that the kernels compute the transcription for every input.

## The pieces

- [`nix/ww3-replay.nix`](../nix/ww3-replay.nix) is the shell `nix develop .#ww3-replay`. It
  fetches WW3 from MetOcean's fork at tag `7.14.mos-92e2cf6`, commit
  `92e2cf66af6e15ae80eb12562f2b05d4a2d75df5` (the pin of `ocean-triton/PLAN.md`). It builds WW3
  with WW3's own CMake (`Release`), unchanged, with the switch of the regression test `ww3_ts1`
  (`ST4 NL1 BT1 DB1`; the build stops if the switch file moves at the pin). gfortran, CMake and
  NetCDF come from `flake.lock`'s nixpkgs.
- [`ww3_capture.F90`](ww3_capture.F90) links that build's `libww3.a`. It reads `mod_def.ww3`
  as `ww3_uprstr` does, and W3IOGR then calls INSNL1, so the DIA's tables are WW3's own. It
  reads the spectrum of a restart that `ww3_shel` wrote. Then it calls the three routines as
  W3SRCE calls them (`w3srcemd.F90:1258`, `:1319`, `:1337`), with the means of W3SPR4 and the
  wavenumbers of WAVNU1. It writes every input and output with nine significant digits, which
  read back to the same float32. Nothing inside WW3 is changed or printed.
- [`run.sh`](run.sh) runs `ww3_grid`, `ww3_strt` and `ww3_shel` on the test's own input, with
  one restart written at 06:00 of the first day (the test writes none), in three cases:

  | Case | Change to the test's input | What it reaches |
  |---|---|---|
  | `deep` | none: 2500 m | W3SBT1 and W3SDB1 give zero |
  | `shallow` | depth scale -6 instead of -2500: 6 m | W3SBT1 on part of the spectrum, both branches of `k d > 6` |
  | `surf` | depth scale -2, minimum depth 1 m instead of 5.75 | W3SDB1 breaks (`LBREAK` true) |

- [`captures.sha256`](captures.sha256) holds the sha256 of the three captures, not the captures
  (36,344 lines each). The check runs WW3 again, writes fresh captures, requires these hashes,
  and replays the fresh files. To keep the captures, run `ww3-replay/run.sh OUTDIR`.
- [`replay.py`](replay.py) turns WW3's tables into the 0-based positions of
  `agda/src/OceanTriton/W3SNL1.agda` and runs the printed launches. This translation of indices
  is its only part that is not printed from Agda.

## Run it

```bash
just ww3-replay          # checks/ww3-replay.sh: WW3 builds, its captures have the committed hashes, the replay is bit for bit, self-test
just ww3-replay-write    # run WW3 again and write the captures' hashes into captures.sha256
ww3-replay/run.sh DIR    # run WW3 and write the three captures into DIR, to read or replay them
```

After a change that moves the captures on purpose (the pin, the switch, a case of `run.sh`, or
`ww3_capture.F90`), run `just ww3-replay-write`, then `just ww3-replay`, and commit the new
`captures.sha256` with the change.

The self-test prints one `+` of the S kernel of W3SNL1 as `-`, and changes one captured output
of WW3 by a part in 1000. Each change must fail the replay.

## What is not checked

- **One test, one point, one time.** The captures are three states of `ww3_ts1`, a one-point
  test without propagation. Other switches, grids and states are not replayed.
- **The compiler of the reference.** WW3 is built by gfortran 16.2 at `-O3`
  (CMake's `Release`) on x86-64. Another compiler or flag can change WW3's own bits. The
  replay compares with this build only.
- **Not on a GPU.** `--device cuda` exists and has not run. A GPU's float32 arithmetic may
  contract a multiply and an add, which the CPU interpreter does not do.
- **W3SDB1** works in double precision and needs `EXP`, `TANH` and `DSQRT`. Its kernel needs
  function leaves in the gather language first (`ocean-triton/PLAN.md`, M4).
