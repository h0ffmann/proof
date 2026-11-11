{-# OPTIONS --safe --without-K #-}

-- Fractional steps and source sub-steps. New: the Lean original has one model step only.
--
-- WAVEWATCH III integrates the action balance equation
--
--     ∂N/∂t + ∇·(ċ N) = S / σ
--
-- by fractional steps: in each global time step, it applies the propagation steps one after
-- the other, then the source step. This is Lie splitting: the step of the model is the
-- composition B ∘ A of the partial steps, not the exact solution of the full equation. The
-- source step Δt is itself split into sub-steps h₁, ..., h_m with h₁ + ... + h_m = Δt (the
-- dynamic time step of the source integration, Tolman 1992, J. Phys. Oceanogr. 22, 1095-1111;
-- not checked against the WW3 source here). Each sub-step uses the semi-implicit update of
-- `OceanWaves.Sources`:
--
--     N ← linStep h β γ N = N (1 + h β) / (1 + h γ).
--
-- This module proves, for fields ℕ → ℚ on n cells and the total Σ_{i<n} N(i):
--
-- * Lie splitting. If step A and step B each keep the total, so does A then B (`then-total`).
--   The same holds for non-negativity (`then-nonneg`) and for "the total does not grow on a
--   non-negative field" (`then-nogain`, which also needs A to keep non-negativity). The three
--   results extend to any finite list of steps (`chain-total`, `chain-nonneg`, `chain-nogain`).
-- * Sub-stepping. Over any list of non-negative sub-steps, repeated `linStep` keeps N ≥ 0
--   when β ≥ 0 and γ ≥ 0 (`subRun-nonneg`), and with β = 0 it never increases N
--   (`subRun-damps`). A `Split Δt` is a list of non-negative sizes with sum Δt; each size is
--   at most Δt (`split-le`). On a field, the sub-stepped source step keeps non-negativity and,
--   with no input, does not increase the total (`sources-nonneg`, `sources-nogain`). So
--   propagation that keeps the total, followed by damping sources, does not increase the total
--   (`fractional-nogain`).
-- * Strang splitting. The symmetric composition A(½) then B then A(½) keeps the total and
--   non-negativity, and does not increase the total (`strang-total`, `strang-nonneg`,
--   `strang-nogain`). These are corollaries of the list results.
--
-- Limits. The steps are abstract functions, so nothing here measures the splitting error. The
-- limiter of the source step is not modelled: the sub-steps use the linear part only. The
-- examples show that sub-steps do not equal one step of the same total size.
module WaveTheory.Splitting where

open import Data.Integer using () renaming (+_ to ℤ+)
open import Data.List using (List; []; _∷_)
open import Data.List.Relation.Unary.All as All using (All; []; _∷_)
open import Data.Nat as ℕ using (ℕ)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _/_; _+_; _*_; _≤_; _<_; _≤?_; _<?_)
open import Data.Rational.Properties using (≤-refl; ≤-trans; <⇒≢)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_)
open import Relation.Nullary.Decidable using (from-yes)
open import Relation.Binary.PropositionalEquality using (_≡_; _≢_; refl; trans; subst)

open import OceanWaves.Order
open import OceanWaves.Sums
open import OceanWaves.Sources using (linStep; linStep-nonneg; linStep-damps)
open import WaveTheory.Algebra using (sumTo-mono)

-- ---------------------------------------------------------------------------------------------
-- Fields, steps and the three properties

Field : Set
Field = ℕ → ℚ

Step : Set
Step = Field → Field

total : ℕ → Field → ℚ
total n F = sumTo n F

NonNeg : ℕ → Field → Set
NonNeg n F = ∀ i → i ℕ.< n → 0ℚ ≤ F i

-- The step keeps the total of the n cells exactly.
KeepsTotal : ℕ → Step → Set
KeepsTotal n A = ∀ F → total n (A F) ≡ total n F

-- The step keeps every one of the n cells non-negative.
KeepsNonNeg : ℕ → Step → Set
KeepsNonNeg n A = ∀ F → NonNeg n F → NonNeg n (A F)

-- On a non-negative field, the step does not increase the total.
NoGain : ℕ → Step → Set
NoGain n A = ∀ F → NonNeg n F → total n (A F) ≤ total n F

-- ---------------------------------------------------------------------------------------------
-- Lie splitting: A then B

infixr 5 _▷_
_▷_ : Step → Step → Step
(A ▷ B) F = B (A F)

then-total : ∀ {n A B} → KeepsTotal n A → KeepsTotal n B → KeepsTotal n (A ▷ B)
then-total hA hB F = trans (hB _) (hA F)

then-nonneg : ∀ {n A B} → KeepsNonNeg n A → KeepsNonNeg n B → KeepsNonNeg n (A ▷ B)
then-nonneg hA hB F hF = hB _ (hA F hF)

then-nogain : ∀ {n A B} → KeepsNonNeg n A → NoGain n A → NoGain n B → NoGain n (A ▷ B)
then-nogain hA⁺ hA hB F hF = ≤-trans (hB _ (hA⁺ F hF)) (hA F hF)

-- A step that keeps the total exactly does not increase it.
total⇒nogain : ∀ {n A} → KeepsTotal n A → NoGain n A
total⇒nogain {n} {A} hA F _ = subst (total n (A F) ≤_) (hA F) ≤-refl

-- A finite list of steps, applied from the head.
chain : List Step → Step
chain []       F = F
chain (A ∷ As) F = chain As (A F)

chain-total : ∀ {n As} → All (KeepsTotal n) As → KeepsTotal n (chain As)
chain-total []         F = refl
chain-total {n} (hA ∷ hAs) F = trans (chain-total {n} hAs _) (hA F)

chain-nonneg : ∀ {n As} → All (KeepsNonNeg n) As → KeepsNonNeg n (chain As)
chain-nonneg []         F hF = hF
chain-nonneg (hA ∷ hAs) F hF = chain-nonneg hAs _ (hA F hF)

chain-nogain : ∀ {n As} → All (KeepsNonNeg n) As → All (NoGain n) As → NoGain n (chain As)
chain-nogain []           []         F hF = ≤-refl
chain-nogain (hA⁺ ∷ hAs⁺) (hA ∷ hAs) F hF =
  ≤-trans (chain-nogain hAs⁺ hAs _ (hA⁺ F hF)) (hA F hF)

-- ---------------------------------------------------------------------------------------------
-- Strang splitting: A(½) then B then A(½)

strang : Step → Step → Step
strang Ah B = chain (Ah ∷ B ∷ Ah ∷ [])

strang-total : ∀ {n Ah B} → KeepsTotal n Ah → KeepsTotal n B → KeepsTotal n (strang Ah B)
strang-total {n} hA hB = chain-total {n} (hA ∷ hB ∷ hA ∷ [])

strang-nonneg : ∀ {n Ah B} → KeepsNonNeg n Ah → KeepsNonNeg n B → KeepsNonNeg n (strang Ah B)
strang-nonneg hA hB = chain-nonneg (hA ∷ hB ∷ hA ∷ [])

strang-nogain : ∀ {n Ah B} → KeepsNonNeg n Ah → KeepsNonNeg n B → NoGain n Ah → NoGain n B →
  NoGain n (strang Ah B)
strang-nogain hA⁺ hB⁺ hA hB = chain-nogain (hA⁺ ∷ hB⁺ ∷ hA⁺ ∷ []) (hA ∷ hB ∷ hA ∷ [])

-- ---------------------------------------------------------------------------------------------
-- Source sub-steps

sumL : List ℚ → ℚ
sumL []       = 0ℚ
sumL (h ∷ hs) = h + sumL hs

-- The semi-implicit update over each sub-step in turn, for one bin.
subRun : ℚ → ℚ → List ℚ → ℚ → ℚ
subRun β γ []       N = N
subRun β γ (h ∷ hs) N = subRun β γ hs (linStep h β γ N)

-- With β ≥ 0, γ ≥ 0 and every sub-step h ≥ 0, N stays non-negative.
subRun-nonneg : ∀ {β γ hs N} → All (0ℚ ≤_) hs → 0ℚ ≤ β → 0ℚ ≤ γ → 0ℚ ≤ N →
  0ℚ ≤ subRun β γ hs N
subRun-nonneg []         hβ hγ hN = hN
subRun-nonneg (hh ∷ hhs) hβ hγ hN = subRun-nonneg hhs hβ hγ (linStep-nonneg hh hβ hγ hN)

-- With no input (β = 0), the sub-steps only damp.
subRun-damps : ∀ {γ hs N} → All (0ℚ ≤_) hs → 0ℚ ≤ γ → 0ℚ ≤ N → subRun 0ℚ γ hs N ≤ N
subRun-damps []         hγ hN = ≤-refl
subRun-damps (hh ∷ hhs) hγ hN =
  ≤-trans (subRun-damps hhs hγ (linStep-nonneg hh ≤-refl hγ hN)) (linStep-damps hh hγ hN)

sumL-nonneg : ∀ {hs} → All (0ℚ ≤_) hs → 0ℚ ≤ sumL hs
sumL-nonneg []         = ≤-refl
sumL-nonneg (hh ∷ hhs) = +-nonneg hh (sumL-nonneg hhs)

-- Each non-negative size is at most the sum of the list.
sizes-le-sum : ∀ {hs} → All (0ℚ ≤_) hs → All (_≤ sumL hs) hs
sizes-le-sum []                      = []
sizes-le-sum {h ∷ hs} (hh ∷ hhs) =
  by-diff {a = h} {b = h + s} s (solve 2 (λ x y → (x :+ y) :- x := y) refl h s) (sumL-nonneg hhs)
  ∷ All.map (λ x≤s → ≤-trans x≤s s≤h+s) (sizes-le-sum hhs)
  where
  s = sumL hs
  s≤h+s : s ≤ h + s
  s≤h+s = by-diff {a = s} {b = h + s} h (solve 2 (λ x y → (x :+ y) :- y := x) refl h s) hh

-- A split of the source step Δt into sub-steps.
record Split (Δt : ℚ) : Set where
  constructor split
  field
    sizes        : List ℚ
    sizes-nonneg : All (0ℚ ≤_) sizes
    sizes-sum    : sumL sizes ≡ Δt
open Split public

-- Every sub-step is at most Δt.
split-le : ∀ {Δt} (s : Split Δt) → All (_≤ Δt) (sizes s)
split-le {Δt} s = subst (λ t → All (_≤ t) (sizes s)) (sizes-sum s) (sizes-le-sum (sizes-nonneg s))

-- A split exists only for Δt ≥ 0.
split-Δt-nonneg : ∀ {Δt} (s : Split Δt) → 0ℚ ≤ Δt
split-Δt-nonneg s = subst (0ℚ ≤_) (sizes-sum s) (sumL-nonneg (sizes-nonneg s))

-- The sub-stepped source step on a field, with input β i and damping γ i in bin i.
sources : (β γ : Field) → List ℚ → Step
sources β γ hs F i = subRun (β i) (γ i) hs (F i)

sources-nonneg : ∀ {n β γ hs} → All (0ℚ ≤_) hs → NonNeg n β → NonNeg n γ →
  KeepsNonNeg n (sources β γ hs)
sources-nonneg hhs hβ hγ F hF i i<n = subRun-nonneg hhs (hβ i i<n) (hγ i i<n) (hF i i<n)

-- With no input, the sources do not increase the total.
sources-nogain : ∀ {n γ hs} → All (0ℚ ≤_) hs → NonNeg n γ → NoGain n (sources (λ _ → 0ℚ) γ hs)
sources-nogain {n} {γ} {hs} hhs hγ F hF =
  sumTo-mono n (sources (λ _ → 0ℚ) γ hs F) F (λ i i<n → subRun-damps hhs (hγ i i<n) (hF i i<n))

-- One global step: propagation P, then the sub-stepped sources with no input. If P keeps the
-- total and non-negativity, the step keeps non-negativity and does not increase the total.
fractional-nonneg : ∀ {n P γ hs} → KeepsNonNeg n P → All (0ℚ ≤_) hs → NonNeg n γ →
  KeepsNonNeg n (P ▷ sources (λ _ → 0ℚ) γ hs)
fractional-nonneg hP hhs hγ = then-nonneg hP (sources-nonneg hhs (λ _ _ → ≤-refl) hγ)

fractional-nogain : ∀ {n P γ hs} → KeepsTotal n P → KeepsNonNeg n P → All (0ℚ ≤_) hs →
  NonNeg n γ → NoGain n (P ▷ sources (λ _ → 0ℚ) γ hs)
fractional-nogain hP hP⁺ hhs hγ = then-nogain hP⁺ (total⇒nogain hP) (sources-nogain hhs hγ)

-- ---------------------------------------------------------------------------------------------
-- Examples: damp N = 4 with γ = 1 and no input, over Δt = 1.

private
  half quarter : ℚ
  half    = ℤ+ 1 / 2
  quarter = ℤ+ 1 / 4

-- Three sub-steps 1/2, 1/4, 1/4, and one step of 1. Both are splits of Δt = 1.
three : Split 1ℚ
three = split (half ∷ quarter ∷ quarter ∷ [])
  (from-yes (0ℚ ≤? half) ∷ from-yes (0ℚ ≤? quarter) ∷ from-yes (0ℚ ≤? quarter) ∷ [])
  refl

one : Split 1ℚ
one = split (1ℚ ∷ []) (from-yes (0ℚ ≤? 1ℚ) ∷ []) refl

-- One step: 4 / (1 + 1) = 2.
one-value : subRun 0ℚ 1ℚ (sizes one) (lit 4) ≡ lit 2
one-value = refl

-- Three sub-steps: 4 / (3/2) = 8/3, then 8/3 / (5/4) = 32/15, then 32/15 / (5/4) = 128/75.
three-value : subRun 0ℚ 1ℚ (sizes three) (lit 4) ≡ ℤ+ 128 / 75
three-value = refl

-- Both are non-negative and at most 4.
three-nonneg : 0ℚ ≤ subRun 0ℚ 1ℚ (sizes three) (lit 4)
three-nonneg = subRun-nonneg (sizes-nonneg three) ≤-refl (from-yes (0ℚ ≤? 1ℚ)) (from-yes (0ℚ ≤? lit 4))

three-damps : subRun 0ℚ 1ℚ (sizes three) (lit 4) ≤ lit 4
three-damps = subRun-damps (sizes-nonneg three) (from-yes (0ℚ ≤? 1ℚ)) (from-yes (0ℚ ≤? lit 4))

-- The split is not one step: 128/75 < 2. The exact decay 4 e⁻¹ is about 1.47, so here the
-- sub-steps come closer to it.
three-below-one : subRun 0ℚ 1ℚ (sizes three) (lit 4) < subRun 0ℚ 1ℚ (sizes one) (lit 4)
three-below-one = from-yes (ℤ+ 128 / 75 <? lit 2)

three-differs : subRun 0ℚ 1ℚ (sizes three) (lit 4) ≢ subRun 0ℚ 1ℚ (sizes one) (lit 4)
three-differs = <⇒≢ three-below-one
