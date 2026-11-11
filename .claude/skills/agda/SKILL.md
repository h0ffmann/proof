---
name: agda
description: Write, prove and type-check Agda in this repository (agda/, the contextual bandit for every K) with the standard library and the Nix shell .#agda. Use when the user asks for Agda code or an Agda proof, a port of a Lean, Z3 or Haskell definition to Agda, or when `just agda` or checks/agda.sh fails.
---

# Agda in this repository

`agda/` is an Agda library (`agda/contextual-bandit.agda-lib`, depends on `standard-library`
only). It holds the decision layer of the contextual bandit and its theorems for every number of
arms K, and ports of other topics: the cycle clock (`Cycle`, from Lean), upwind advection
(`OceanWaves`, from Lean) and the triangle-grid size rules (`Grids`, from Z3). Agda is the
specification of the bandit since `z3-scala/` was removed (2026-11-11); it kept the Z3 names,
with `-` for `_` (`ucb_gap` is `ucb-gap`). Read `agda/README.md` first: it has the
modules, the theorem table and how Agda differs from Z3 and from the Lean original.

## Toolchain

- `nix develop .#agda` gives Agda and the standard library, from `nix/agda.nix`. The versions
  (Agda 2.8.0, standard library 2.3) are asserted there against the nixpkgs that `flake.lock`
  pins. Never install Agda with cabal, stack or a package manager.
- A version bump: update the lock (or the nixpkgs it follows), change the two versions in
  `nix/agda.nix`, run `just agda`, and say in the PR what changed.
- Agda prints Unicode. Outside the shell, set `LANG=C.UTF-8 LC_ALL=C.UTF-8`, or an error message
  ends in `commitBuffer: invalid argument`.

## Check

```bash
just agda                       # checks/agda.sh --self-test: hygiene, self-test, type-check
bash checks/agda.sh             # hygiene and type-check only (just check runs this one)
cd agda/src && agda ContextualBandit/Theorems.agda   # one module, inside nix develop .#agda
```

A module is checked when Agda prints `Checking ...` lines and no `error:`. Interface files go to
`agda/_build/` (ignored by git).

## Rules

1. **Every file starts with `{-# OPTIONS --safe --without-K #-}`.** `--safe` refuses
   `postulate`, `{-# TERMINATING #-}`, `{-# NON_TERMINATING #-}`, `primTrustMe` and the other
   escapes, so a module that type-checks has only complete proofs. `checks/agda.sh` fails on a
   file without `--safe`. Never remove it to get a proof through.
2. **A new module is imported by a root**, a file `agda/src/<Topic>.agda` (`ContextualBandit`,
   `Cycle`, `OceanWaves`, `Grids`), or nothing checks it. `checks/agda.sh` type-checks every
   root, so a new topic is a new root and needs no change to the script.
3. **Agda first.** A rule or model goes into Agda first, with its theorem (AGENTS.md, rule 2). Then
   it goes into Haskell with the same name, argument order and tie-break. Argmax keeps
   the first maximum: the running best changes only on a strict `<`.
4. **Decision rules see only estimates** (AGENTS.md, rule 4): a `DecisionRule K` is
   `(Arm K → Estimate) → Decision K`, never a function of the history or the context.
5. **Examples check by `refl`.** Put concrete numbers in `Examples.agda` as equalities that hold
   by `refl` (Agda computes the exact rationals). For a decidable side condition on concrete
   numbers, use `from-yes (p ≤? q)`. The self-test of `checks/agda.sh` changes one number in
   `Examples.agda` (`+ 14 / 15`) and expects a failure: keep that literal, or change the sed in
   the self-test with it.
6. **English, ASD-STE100 comments** (AGENTS.md, "Language"). A module opens with a comment block
   that says what it holds and which Lean, Z3 or Haskell original it follows.

## Traps of the standard library (2.3)

- **No function extensionality** under `--safe --without-K`. State equality of decisions arm by
  arm: `∀ a → d a ≡ e a`, not `d ≡ e`.
- **Name clashes**: `Data.Fin.Properties` and `Data.Rational.Properties` both export `_≟_`.
  Open the rational one with `hiding (_≟_)`.
- **Monotonicity names are by the side that stays**: `+-monoˡ-≤ r : p ≤ q → p + r ≤ q + r`
  adds `r` on the **right**; `+-monoʳ-≤ r : p ≤ q → r + p ≤ r + q`.
- **Instance arguments**: `1/_`, `*-inverseʳ`, `nonNegative⁻¹` and the `…⇒nonNeg` lemmas take
  `NonZero`, `Positive` or `NonNegative` as instances. Pass them by hand with `{{ … }}`, and give
  the rational explicitly (`nonNegative⁻¹ (invK (suc K)) {{…}}`, not `_`): an underscore there
  leaves unsolved metas. Build the instance from a proof with `nonNegative`, `positive`,
  `pos⇒nonZero`, `pos⇒nonNeg`.
- **`NonZero K` on `ℕ`**: to get an element of `Fin K`, match `K` as `suc _` (see `firstArm` in
  `Argmax.agda`); instance search finds `NonZero (suc n)` by itself.
- **Ring equalities**: use the solver, not a chain of `+-assoc` and `+-comm`:

  ```agda
  open import Data.Rational.Solver using (module +-*-Solver)
  open +-*-Solver using (solve; _:=_; _:+_; _:*_; _:-_; con)

  split : ∀ x y → x + y ≡ (x - y) + 2ℚ * y
  split = solve 2 (λ x y → x :+ y := (x :- y) :+ (con 1ℚ :+ con 1ℚ) :* y) refl
  ```

  `p - q` is `p + - q` by definition, so `:-` matches it.
- **Case on a decision with `with does (a ≟ b)`**, then `true` and `false`. The definitions use
  `if does (a ≟ b) then … else …`, so the goal reduces in each branch. `does (map′ …)` reduces to
  the inner `does`, so `point (suc b) (suc a)` is `point b a` by computation.
- **Sums**: `mass d = foldr _+_ 0ℚ (tabulate d)`. `tabulate {suc K} d` is
  `d zero ∷ tabulate (d ∘ suc)` by definition, so a sum lemma goes by induction on K with
  `cong₂ _+_` and needs no lemma about `map` or `allFin`.
- **A `with` on a rational decision does not abstract** (`with x ≤? 3ℚ`): the goal unfolds
  `_≤?_` to integer arithmetic first. Define the branch as a function of the answer
  (`clamp x (yes _) = pade x`) and prove each lemma by matching on a `Dec` argument
  (`OceanWaves/Dispersion.agda`, `Bisection.agda`). On ℕ, `does (j ≟ a)` reduces to
  `j ≡ᵇ a`: define with `≡ᵇ` and use `with j ≡ᵇ a in eq` (`OceanWaves/Sums.agda`, `pick`).
- **Division**: `_÷_` needs a `NonZero` instance. To port Lean's total division use `_/₀_` of
  `OceanWaves/Order.agda`, and prove an inequality with `by-diff`: `a ≤ b` from `b - a ≡ e`
  (the solver, with `inv₀ q` as a variable) and `0 ≤ e` (`*-nonneg`, `sq-nonneg`).
- **`∣_-_∣` of `Data.Nat` recurses in unary.** On 50-bit numbers a type that mentions it does
  not finish checking. Use `_∸_` and `_≤ᵇ_`, which are built in (`gap` in
  `PortAudit/Division.agda`), and turn a Boolean comparison into a proof with `≤ᵇ⇒≤` and `<ᵇ⇒<`.
- **Give the implicit arguments of the `OceanWaves.Order` division lemmas** (`div-le-of-le-mul`,
  `div-le-div-of-cross`): Agda cannot read them back from `a * inv₀ b`.
- **Unsolved metas in `trans … (+-comm _ _)`**: give the arguments of `+-comm`, `+-identityʳ` and
  similar lemmas when the other side of `trans` does not fix them.

## Port from Lean

| Lean 4 (core) | Agda (standard library) |
|---|---|
| `Rat`, `(K : Rat)⁻¹` | `ℚ`, `invK K` (`1/ ofℕ K`, `0` when K = 0) |
| `Fin K`, `List.finRange K` | `Fin K`, `allFin K` or `tabulate` |
| `[NeZero K]` | `{{_ : NonZero K}}` |
| `structure` with fields | `record` with `field`, plus `open R public` for the projections |
| `x ∈ l`, `List.mem_cons` | `_∈_` of `Data.List.Membership.Propositional`, `here` / `there` |
| `grind`, `simp`, `omega` | the solver above, `≤-trans` chains, `subst`, `rewrite` |
| `native_decide`, `#eval` | `refl` on a closed term, `from-yes` on a decidable relation |
| `funext` | not available: state it arm by arm |
| `if i = 0 then b else N (i - 1)` | match on `i` (`upstream b N zero = b`), so each case reduces |
| `Fin (n + 1)` with `Fin.ext` | `Fin (suc n)`, `toℕ-injective`, the `_%_` lemmas of `Data.Nat.DivMod` |

## Port from Z3

- A Z3 statement over a fixed number of unknowns (a chain of 8 sizes) often becomes an
  induction in Agda (a chain of any length). Prove the general bound, then read it at the
  numbers Z3 checks (`Grids/SizeRule.agda`).
- A Z3 `counterexample` becomes a witness: a value that meets the premises and breaks the
  conclusion, checked with `from-yes` (`growth-7-steps-reach-30km`).
- `ite(c, a, b)` is `if does (p <? q) then a else b`. In a proof, case on it with
  `with does (p <? q) in eq` and use `dec-true` or `dec-false`: a `with` on the bare `p <? q`
  does not abstract once the constants unfold.
