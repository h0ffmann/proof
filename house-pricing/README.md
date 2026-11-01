# House pricing: Rust trains, Lean replicates and proves

A machine learning app for California house prices. Rust loads the data,
engineers features, trains and compares seven models. The best model that Lean
can **replicate exactly** is exported, evaluated in Lean 4 over exact `Rat`,
and called from Rust through the C ABI that Lean compiles to. Lean also proves
properties that hold for every input, not only for the test set.

```
 data/housing.csv ─► Rust: load, filter, features, train 7 models ─► model/gbt.txt
                                                                      model/gbt-monotone.txt
                                                                            │ include_str
                                                                            ▼
 Rust parity ◄── C ABI: hp_predict(double…, uint8_t) ◄── lake build ◄── Lean: Tree, Ensemble,
 (Lean vs Rust                                           HousePricing:static   theorems, certificates
  on the test set)
```

## Result

Data: California Housing (Pace and Barry, 1997, from the 1990 US census), one
row per block group. Of 20 640 rows, 207 have no `total_bedrooms` and 958 have
the censored value 500 001, so 19 475 are kept. Split: 80 % train (fit 80 % +
validation 20 %), 20 % test, fixed seeds. Hyperparameters are chosen on
validation, and the test set is used once. RMSE and MAE are in US dollars.

| Model | Lean replicates it exactly? | Val RMSE | Test RMSE | Test R² |
|---|---|---:|---:|---:|
| mean | yes, a constant | 99 273 | 99 459 | -0.002 |
| ridge, 15 features | yes, a dot product | 62 323 | 60 542 | 0.629 |
| ridge, quadratic features | yes, a dot product | 65 408 | 62 124 | 0.609 |
| regression tree, depth 14 | yes, comparisons | 52 995 | 51 281 | 0.734 |
| **gradient boosting, depth 6, 537 trees (chosen)** | yes, comparisons and a sum | **40 830** | **40 572** | **0.833** |
| gradient boosting, monotone in income | yes, comparisons and a sum | 41 580 | 41 239 | 0.828 |
| gradient boosting on log(value) | **no**, needs `exp` | 42 245 | 41 883 | 0.822 |

The full table, with MAE and model sizes, is [`model/report.md`](model/report.md).
"Lean replicates it exactly" means Lean computes the same prediction from the
same constants with no approximation: trees are comparisons, ridge is a dot
product. A model on log(price) needs `exp`, which core Lean does not define on
`Rat`, so it is not a candidate (it also scores lower here).

Parity, Lean through the C ABI against Rust, on the 3 895 test rows:

```
chosen   3895 test rows: max |Lean - Rust| = 1.05e-9 dollars, rows off by a cent or more: 0
monotone 3895 test rows: max |Lean - Rust| = 6.40e-10 dollars, rows off by a cent or more: 0
```

Every leaf is a whole number of cents, so taking a different path through any
tree would move the sum by at least a cent. The remaining 1e-9 is `f64`
rounding in Rust's sum.

## What is proved

All in [`lean/HousePricing/Theorems.lean`](lean/HousePricing/Theorems.lean), with
no `sorry`. The theorems hold for **every** tree ensemble, so for any model the
trainer can export.

| Theorem | Statement |
|---|---|
| `Tree.lo_le_eval`, `Tree.eval_le_hi` | a tree's output lies between its smallest and largest leaf |
| `Ensemble.predict_bounds`, `predictRaw_bounds` | every prediction lies in `[m.lo, m.hi]`, two numbers computed from the model alone |
| `Tree.eval_mono`, `Ensemble.predict_mono` | if the certificate `monoIn j` passes, the prediction never decreases when feature `j` grows and the others stay fixed |
| `features_income` | changing a row's income changes only feature 0 |
| `income_monotone` | end to end on raw rows: if the certificate passes for income, a higher income never gives a lower price, all else equal |

[`lean/HousePricing/Examples.lean`](lean/HousePricing/Examples.lean) applies them to
the two trained models (`native_decide` runs the certificate checks there and
nowhere else):

| Fact | Result |
|---|---|
| `monotone_cert`, `monotone_income` | the monotone model **is** monotone in income, for every input |
| `chosen_not_mono` | the chosen model is **not**: a higher income lowers its price somewhere |
| `chosen_bounds` | the chosen model's price is in [-1 190 580, 1 935 237] dollars for every input |

So the choice is a trade: the chosen model scores 1.6 % better on test RMSE,
the monotone model has a guarantee. Both run in Lean. The bounds are loose,
because they add each tree's extreme leaf; they show that no input, however odd,
produces an unbounded price, not that prices are positive.

## Why Lean and Rust agree exactly

Lean computes features over exact `Rat`, Rust over `f64`. A test row whose
exact feature value sits on a threshold would go left in one and right in the
other. Two choices remove that case:

1. **Whole-number units.** Longitude and latitude are in hundredths of a
   degree, income in dollars. Every raw value is then a whole number, exact in
   `f64`, and so are `lat + lon` and `lat - lon`. Only the three ratios are
   rounded, once each.
2. **Dyadic thresholds.** Each threshold is a number `m / 2^k`, `k ≤ 30`, in
   the middle half between two training values. It is an `f64` exactly, and the
   model file holds its exact decimal expansion. A ratio `p / q` with
   `p < 2^16` that differs from such a threshold differs by at least
   `1 / (q 2^k)`, more than the half ulp Rust's division can lose. So both sides
   always compare the same way. `short_between` in
   [`rust/src/tree.rs`](rust/src/tree.rs) has the argument.

The first version used short decimal thresholds (`152.35`) and fractional
degrees; about 10 % of test rows then took a different path. The parity test is
what found it.

## Layout

```
data/fetch.sh              download housing.csv (pinned commit + SHA-256); the CSV is not committed
rust/                      cargo package, std only, no dependencies
  src/data.rs              load, filter, whole-number units, seeded split (SplitMix64)
  src/features.rs          the 15 features (mirrors Lean `features`)
  src/linear.rs            ridge regression, closed form (Cholesky)
  src/tree.rs              histogram trees, gradient boosting, monotone constraint, dyadic thresholds
  src/export.rs            model text format; writes lean/HousePricing/Trained.lean
  src/lean_ffi.rs          the Lean model through its C ABI (feature `lean`)
  build.rs                 links libHousePricing.a and the Lean runtime
model/                     generated by `train`: gbt.txt, gbt-monotone.txt, report.md
lean/                      Lean 4 package `HousePricing`, core only, toolchain v4.24.0
  HousePricing/Features.lean   Raw, Ocean, features
  HousePricing/Tree.lean       Tree, Ensemble, predict, lo, hi, monoIn
  HousePricing/Theorems.lean   the proofs
  HousePricing/Parse.lean      model text -> Ensemble (exact decimals)
  HousePricing/Trained.lean    the two models, via include_str (generated)
  HousePricing/FFI.lean        @[export hp_predict] and friends
  HousePricing/Examples.lean   certificates and #eval on the trained models
```

| Concept | Lean | Rust |
|---|---|---|
| Raw row | `Raw` (Rat fields, `Ocean`) | `data::Raw` (whole-number `f64`, `u8` code) |
| Features | `features : Raw → Fin 15 → Rat` | `features::features(&Raw) -> [f64; 15]` |
| Tree | `Tree n` (`leaf v`, `node f t l r`, left when `x f ≤ t`) | `tree::Node` |
| Model | `Ensemble n {base, trees}`, `predict` | `tree::Ensemble`, `predict` |
| Exported | `hp_predict`, `hp_predict_monotone`, `hp_chosen_lo`, `hp_chosen_hi` | `lean_ffi::predict`, … |

## Run

Needs Rust ≥ 1.82 and the Lean toolchain in `lean/lean-toolchain` (install via
[elan](https://github.com/leanprover/elan)). `just house-pricing` from the repo
root runs all four steps.

```bash
house-pricing/data/fetch.sh                              # data/housing.csv
cd house-pricing/rust && cargo run --release -- train     # ~25 s: compare, export, report
cd ../lean && lake build                                  # proofs, certificates, #evals
lake build HousePricing:static                            # libHousePricing.a for the C ABI
cd ../rust && cargo run --release --features lean -- parity
```

`train` is deterministic: the same CSV gives byte-identical model files. If
you change `features.rs`, change `Features.lean` in the same way; the parity
test fails otherwise.

## Caveats

* The proofs are about exact `Rat` evaluation. Rust's `f64` evaluation is
  covered by the parity test on the test set and the threshold argument above,
  not by a Lean theorem.
* The model file is read by a parser that no theorem covers. The theorems hold
  for whatever ensemble it returns, and `Examples.lean` checks that it parses.
* Dropping the 958 censored rows makes the task easier than the usual
  California Housing benchmark, so these scores are not comparable to results
  that keep them.
* Lean evaluates about 250 rows per second through the C ABI (exact rational
  sums of 537 trees); Rust's `f64` evaluator is far faster. Use Lean as the
  reference, not as the serving path.
* Data licence: the CSV comes from
  [ageron/handson-ml2](https://github.com/ageron/handson-ml2/tree/master/datasets/housing)
  (Apache-2.0), a copy of the StatLib dataset with 207 bedroom values removed and
  `ocean_proximity` added. It is downloaded, not redistributed here.
