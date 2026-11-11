# tools/port-audit: the chaceon audit, in Haskell

The Z3 checks of chaceon, the Rust port of WAVEWATCH III, and the coverage table of
[`port-audit/README.md`](../../port-audit/README.md), which says what each statement means. They
were Scala (`z3-scala/src/main/scala/portaudit/`) and Python before that; this port keeps every
statement and every count.

```sh
tools/port-audit/run.sh chaceon                    # 28 statements; exit 1 if one fails
tools/port-audit/run.sh coverage                   # fetch both pins into port-audit/.cache, print the tables
tools/port-audit/run.sh coverage --write | --check # rewrite the README block, or fail when it is stale
tools/port-audit/run.sh coverage --chaceon DIR --ww3 DIR
bash checks/port-audit-haskell.sh                  # both, as `just check` runs them
```

| File | What it holds |
|---|---|
| `Report.hs` | statements as values (`Proves`, `Refutes`), proved by refutation: Z3 is asked for a model of the premises and the negation of the conclusion; the report's lines and the summary |
| `Chaceon.hs` | groups D (division through `f64`: 100-bit vectors and reals), U (`nint`, `floor`, `sign` over IEEE `f32`) and S (W3SRCE's step over `f32` and over the reals), each with its chaceon `file:line` |
| `Coverage.hs` | the preprocessor and WW3's CMake rules as formulas over one Boolean per macro, the ledger of `rust/ports.tsv`, and the tables; one Z3 process answers every question through SBV's query mode |
| `Pins.hs` | shallow, sparse git checkouts of chaceon and WW3 at their pins |
| `Json.hs` | a small reader for `switches.json` |

A counterexample is printed as SBV gives its model, sorted by name: a bit-vector or an integer as
a number, a real as a decimal or as `p % q`. The model can differ from the Scala's, which is any
model Z3 finds; the verdict cannot.

## Build

`run.sh` enters `nix develop .#port-audit` (`nix/port-audit.nix`) when the tools are not on `PATH`
and builds `Main.hs` with `ghc -O1 -Wall -Werror` into `tools/port-audit/build/`. At the locked
nixpkgs: GHC 9.10.3 with its bundled libraries, SBV 11.7, Z3 5.1.0, and git for the pins.
agda/src/PortAudit/ proves groups D and S over the integers and the rationals for every exponent
and bound, which Z3 checks at two exponents; Agda has no rounding, so group U and the `f32` part of
S are Z3's alone.
