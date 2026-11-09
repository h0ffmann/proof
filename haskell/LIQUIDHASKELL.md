# LiquidHaskell on the Haskell port

[LiquidHaskell](https://ucsd-progsys.github.io/liquidhaskell/) adds refinement types to Haskell.
A refinement type is a Haskell type with a logical predicate, for example
`{v:Int | 0 <= v && v < len xs}`. A GHC plugin sends each obligation to Z3. GHC itself reads
the refinements as comments (`{-@ ... @-}`), so the normal build does not change.

```bash
just liquid                 # self-test, then the check (checks/liquidhaskell.sh)
just checks liquidhaskell   # the check only; `just check` runs it with every other check
just liquid-shell           # GHC with the plugin, and Z3 (nix/liquidhaskell.nix)
```

The script enters `nix develop .#liquidhaskell` when the tools are not on `PATH`. The shell takes
GHC, `liquidhaskell` and Z3 from the nixpkgs that `flake.lock` pins. At that pin the versions are
GHC 9.10.3, liquidhaskell 0.9.10.1.2 and Z3 5.1.0. The check passes when each module is `SAFE`
and no context is false. A false context (LiquidHaskell's "Found false") makes every refinement
in it true, so the script fails on it. The self-test changes `argmax` to return an index past the
end, and the check must then fail.

## What is proved

Modules: `src/ContextualBandit.hs` and `src/Models.hs`.

| Function | Refinement | Meaning |
|---|---|---|
| `argmax` | `{xs:[Double] \| len xs > 0} -> {v:Nat \| v < len xs}` | the index is an arm |
| `point` | `Int -> Arm -> [Prob]` | each entry is 0 or 1, so a probability |
| `uniform` | `{k:Int \| k > 0} -> {v:[Prob] \| len v = k}` | no division by 0; `k` probabilities |
| `mix` | `{w \| 0 <= w <= 1} -> [Prob] -> [Prob] -> [Prob]` | a convex mix of probabilities is a probability |
| `greedy`, `ucb` | `Arms -> [Prob]` | at least one arm in, probabilities out |
| `epsGreedy` | `{eps \| 0 <= eps <= 1} -> Arms -> [Prob]` | the same, for ε in [0, 1] |
| `categorical` | `ps:[Double] -> Rand {v:Int \| v < len ps && (len ps > 0 => v >= 0)}` | the draw is an arm when there is one |
| `normal` | (body) | `log` gets a positive number and `sqrt` a non-negative one |
| `gamma` | `{k \| k > 0} -> Rand {v \| v >= 0 && (k >= 1 => v > 0)}` | no division by 0; positive for shape 1 or more |
| `beta` | `{a \| a >= 1} -> {b \| b >= 1} -> Rand Prob` | `x + y` is not 0; the draw is a probability |
| `betaUpdate` | `Count -> Count -> {r \| 0 <= r <= 1} -> (Count, Count)` | a reward in [0, 1] keeps both counts at 1 or more |
| `betaEstimate` | `Count -> Count -> {e \| 0 <= mean e <= 1 && width e >= 0}` | the posterior mean is a probability; the std is not negative |

`Prob` is `{p:Double | 0 <= p && p <= 1}`, `Arms` is `{est:[Estimate] | len est > 0}` and
`Count` is `{n:Double | n >= 1}`. The Haskell code did not change, with three exceptions: the two
Beta-Bernoulli helpers have names now, `gamma` binds `d` and `c` under its guard, and its
rejection test uses two `if`s in place of `&&`. The output of `cabal run examples` is the same.

## What is trusted

LiquidHaskell does not check these. The check fails when a name here is missing from this table.

| Name | Kind | Why it is trusted |
|---|---|---|
| `sqrt` | `assume` | `x >= 0 => sqrt x >= 0`, and `> 0` for `x > 0`. A fact of IEEE `sqrt` |
| `log` | `assume` | `0 < x <= 1 => log x <= 0`. A fact of a monotone `log` with `log 1 = 0` |
| `(**)` | `assume` | `x >= 0 => x ** y >= 0` |
| `uniform01` | `assume` | its result is in (0, 1]; LiquidHaskell does not know the range of `shiftR` |
| `loop` | `lazy` | the rejection sampler of `gamma` ends with probability 1, not after a bounded number of steps |
| `thompsonArm` | `ignore` | LiquidHaskell does not see that `mapM` keeps the length, and nothing stops `numArms m = 0` |
| `betaBernoulli` | `ignore` | `Obs` lets a reward be any `Double`; `betaUpdate` and `betaEstimate` are checked |
| `shermanMorrison` | `ignore` | its denominator is at least 1 only for a positive semi-definite `A⁻¹` |
| `cholesky` | `ignore` | LiquidHaskell does not see the length of `[0 .. n - 1]`, so it cannot bound `(!!)` |
| `bayesLinear` | `ignore` | `bs !! a` needs `a < k`, and its width needs a positive semi-definite `A⁻¹` |

## What is not covered

- LiquidHaskell reads `Double` as a real number. A proof here does not cover rounding, overflow,
  underflow or NaN (AGENTS.md rule 7 says the same for Z3).
- `src/Video.hs` and `src/Pi.hs` compute with `Rational`. LiquidHaskell 0.9.10 has no numeric SMT
  sort for `Ratio`, so they are not checked.
- `app/` is not checked. A caller there can give `greedy` an empty list; only the type of the
  callee says that it must not.

## What the check found

- `uniform01` can return 1.0, so the comment "Uniform in (0, 1)" was wrong. For
  `w >> 11 = 2^53 - 1` the sum `2^53 - 0.5` rounds to the even `2^53`. In GHC 9.10.3 this
  prints `True`. The callers accept 1.0, so only the comment changed.

  ```bash
  ghc -e 'import Data.Word' -e 'import Data.Bits' \
    -e '(fromIntegral ((maxBound :: Word64) `shiftR` 11) + 0.5) / 9007199254740992 == (1 :: Double)'
  ```

- `betaBernoulli` expects rewards in [0, 1], and nothing checks it. A reward of 2 takes the
  beta count below 1, and the width then takes `sqrt` of a negative number.
- `gamma` with a shape below 1 can return 0: `u ** (1 / k)` underflows (`0.5 ** 1000` is about
  `1e-301`). `beta` divides by `x + y`, so it is safe only for shapes of 1 or more.
  `betaBernoulli` keeps its shapes at 1 or more while rewards stay in [0, 1].
