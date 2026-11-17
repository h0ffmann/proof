# tools/tv-z3: the Z3 checks of the JCS model of tv-audience

Z3 (through SBV) re-checks the theorems of [`agda/src/TvAudience/`](../../agda/src/TvAudience.agda)
about the Joint Competitive Share (JCS) model and its logit fit, the port audit's way: one
statement a line, proved by refutation over the exact reals — a statement holds when Z3 finds no
model of its premises and the negation of its conclusion. The names are the Agda ones. Agda
proves each theorem for every slot length under `--safe --without-K`; Z3 re-checks the shape at
two or three channels here, on the same exact arithmetic (`Real`).

The loss of the logit fit needs the exponential, which neither side has: both take the weights
w = exp(u) ≥ 0 and the observed shares as given, and Z3 checks the residual layer of the gradient
(`resid` = s - s_obs), which is what `fit_logit`'s hand-written gradient reads.

```sh
tools/tv-z3/run.sh          # 17 statements; exit 1 if one fails
bash checks/tv-z3.sh        # the same, as `just check` runs it
```

| Statement | In Agda | What it says |
|---|---|---|
| `jcs-sum` | `Jcs.jcs-sum` | the shares and the outside share add up to 1 |
| `jcs-inside-lt-one` | `Jcs.jcs-inside-lt-one` | so the channels together hold less than the whole pool |
| `jcs-coherent` | `Jcs.jcs-coherent` | the C forecasts of a slot never add up to more than its pool forecast |
| `jcs-iia` | `Jcs.jcs-iia` | the ratio of two shares does not depend on the rivals |
| `jcs-rival` | `Jcs.jcs-rival` | a new rival never raises a channel's share |
| `jcs-odds` | `JcsTheory.jcs-odds` | a share over the outside share is its weight (the log-odds is u) |
| `jcs-own` | `JcsTheory.jcs-own` | a larger weight raises the channel's own share |
| `jcs-cross` | `JcsTheory.jcs-cross` | ... and lowers every rival's |
| `jcs-diversion` | `JcsTheory.jcs-diversion` | a channel that leaves gives its viewers to the rest in proportion |
| `jcs-pool-scale` | `JcsTheory.jcs-pool-scale` | an error of the pool forecast by a factor c moves every forecast by c |
| `jcs-invert` | `JcsTheory.jcs-invert` | shares with a sum below 1 come from the weights s / s₀ |
| `fit-unique` | `LogitFit.fit-unique` | the exact fit is the only one (two channels; Agda: every length) |
| `resid-slot` | `Neural.resid-slot` | the residuals sum over a slot to s₀,obs - s₀ |
| `gradBias-fit` | `LogitFit.gradBias-fit` | at the exact fit, Σ resid = 0 |
| `featureGrad-fit` | `LogitFit.featureGrad-fit` | at the exact fit, Σ resid · z = 0 for every column z |
| `l2-stationary-zero` | `LogitFit.l2-stationary-zero` | if the penalised gradient is 0 at an exact fit, the coefficient is 0 |
| `l2-moves-off` | (the limit of `LogitFit`) | expected counterexample: away from the exact fit the penalised coordinate can be 0 with a non-zero coefficient |

`l2-moves-off` is a `Refutes`: it holds when Z3 finds the counterexample, and its model is the
witness that the L2 pulls the linear part off the exact shares — which is why the experiment's
fitted weights do not reproduce the observed shares exactly.

## Build

`run.sh` enters `nix develop .#tv-z3` ([`nix/tv-z3.nix`](../../nix/tv-z3.nix)) when the tools are
not on `PATH` and builds `Main.hs` with `ghc -O1 -Wall -Werror` into `tools/tv-z3/build/`. At the
locked nixpkgs: GHC with SBV, and Z3 as a process. The statements are non-linear over the reals
(the shares are w / (1 + Σ w)), so Z3 answers through its nonlinear solver; every statement is
small and answers at once.
