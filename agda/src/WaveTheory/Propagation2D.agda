{-# OPTIONS --safe --without-K #-}

-- Two-dimensional propagation by dimensional splitting, and many steps. New: the Lean original
-- advects in one dimension and proves one step.
--
-- The field F x y lives on a periodic grid of (nx + 1) × (ny + 1) cells. One step is an
-- upwind sweep along x with the Courant number cx in every row, then a sweep along y with cy
-- in every column (the fractional steps of WAVEWATCH III's W3XYP1 on a regular grid, with
-- positive speeds). Every result holds for every number of steps:
--
--   - the total action is kept exactly (periodic boundaries);
--   - a non-negative field stays non-negative when 0 ≤ cx, cy ≤ 1;
--   - a field below M stays below M (the discrete maximum principle).
--
-- The last two together say that the scheme is stable in the maximum norm for every run
-- length, which is the property that the CFL condition buys.
module WaveTheory.Propagation2D where

open import Data.Nat as ℕ using (ℕ; zero; suc; _∸_)
open import Data.Nat.Properties using (n<1+n)
open import Data.Product using (_×_; _,_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _≤_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong)

open import OceanWaves.Sums
open import OceanWaves.Advection

-- A 2-D field.
Field : Set
Field = ℕ → ℕ → ℚ

-- The x sweep in every row y, and the y sweep in every column x.
sweepX : ℕ → ℚ → Field → Field
sweepX nx cx F x y = advectPeriodic nx cx (λ x′ → F x′ y) x

sweepY : ℕ → ℚ → Field → Field
sweepY ny cy F x y = advectPeriodic ny cy (λ y′ → F x y′) y

-- One split step: x first, then y.
step2D : ℕ → ℕ → ℚ → ℚ → Field → Field
step2D nx ny cx cy F = sweepY ny cy (sweepX nx cx F)

-- k split steps.
run2D : ℕ → ℕ → ℚ → ℚ → ℕ → Field → Field
run2D nx ny cx cy zero    F = F
run2D nx ny cx cy (suc k) F = step2D nx ny cx cy (run2D nx ny cx cy k F)

-- The total action on the grid of (nx + 1) × (ny + 1) cells.
total2D : ℕ → ℕ → Field → ℚ
total2D nx ny F = sumTo (suc nx) (λ x → sumTo (suc ny) (λ y → F x y))

-- ---------------------------------------------------------------------------------------------
-- Conservation

sweepY-total : ∀ nx ny cy F → total2D nx ny (sweepY (suc ny) cy F) ≡ total2D nx ny F
sweepY-total nx ny cy F =
  sumTo-congr (suc nx) _ _ (λ x _ → advectPeriodic-sum ny cy (λ y′ → F x y′))

sweepX-total : ∀ nx ny cx F → total2D nx ny (sweepX (suc nx) cx F) ≡ total2D nx ny F
sweepX-total nx ny cx F =
  trans (sumTo-comm (suc nx) (suc ny) (λ x y → sweepX (suc nx) cx F x y))
  (trans (sumTo-congr (suc ny) _ _ (λ y _ → advectPeriodic-sum nx cx (λ x′ → F x′ y)))
         (sym (sumTo-comm (suc nx) (suc ny) F)))

step2D-total : ∀ nx ny cx cy F → total2D nx ny (step2D (suc nx) (suc ny) cx cy F) ≡ total2D nx ny F
step2D-total nx ny cx cy F = trans (sweepY-total nx ny cy (sweepX (suc nx) cx F)) (sweepX-total nx ny cx F)

-- Exact conservation for every run length.
run2D-total : ∀ nx ny cx cy k F → total2D nx ny (run2D (suc nx) (suc ny) cx cy k F) ≡ total2D nx ny F
run2D-total nx ny cx cy zero    F = refl
run2D-total nx ny cx cy (suc k) F =
  trans (step2D-total nx ny cx cy (run2D (suc nx) (suc ny) cx cy k F)) (run2D-total nx ny cx cy k F)

-- ---------------------------------------------------------------------------------------------
-- Positivity and the maximum principle

-- The field on the grid satisfies P in every cell.
OnGrid : ℕ → ℕ → (ℚ → Set) → Field → Set
OnGrid nx ny P F = ∀ x y → x ℕ.< suc nx → y ℕ.< suc ny → P (F x y)

-- A Courant number that meets CFL.
Courant : ℚ → Set
Courant c = 0ℚ ≤ c × c ≤ 1ℚ

sweepX-nonneg : ∀ nx ny cx F → Courant cx → OnGrid nx ny (0ℚ ≤_) F → OnGrid nx ny (0ℚ ≤_) (sweepX (suc nx) cx F)
sweepX-nonneg nx ny cx F hc hF x y hx hy =
  advect-nonneg (suc nx) (constCourant cx) (F nx y) (λ x′ → F x′ y) (λ _ _ → hc)
    (hF nx y (n<1+n nx) hy) (λ i hi → hF i y hi hy) x hx

sweepY-nonneg : ∀ nx ny cy F → Courant cy → OnGrid nx ny (0ℚ ≤_) F → OnGrid nx ny (0ℚ ≤_) (sweepY (suc ny) cy F)
sweepY-nonneg nx ny cy F hc hF x y hx hy =
  advect-nonneg (suc ny) (constCourant cy) (F x ny) (λ y′ → F x y′) (λ _ _ → hc)
    (hF x ny hx (n<1+n ny)) (λ j hj → hF x j hx hj) y hy

step2D-nonneg : ∀ nx ny cx cy F → Courant cx → Courant cy → OnGrid nx ny (0ℚ ≤_) F →
  OnGrid nx ny (0ℚ ≤_) (step2D (suc nx) (suc ny) cx cy F)
step2D-nonneg nx ny cx cy F hx hy hF =
  sweepY-nonneg nx ny cy (sweepX (suc nx) cx F) hy (sweepX-nonneg nx ny cx F hx hF)

run2D-nonneg : ∀ nx ny cx cy → Courant cx → Courant cy → ∀ k F → OnGrid nx ny (0ℚ ≤_) F →
  OnGrid nx ny (0ℚ ≤_) (run2D (suc nx) (suc ny) cx cy k F)
run2D-nonneg nx ny cx cy hx hy zero    F hF = hF
run2D-nonneg nx ny cx cy hx hy (suc k) F hF =
  step2D-nonneg nx ny cx cy (run2D (suc nx) (suc ny) cx cy k F) hx hy (run2D-nonneg nx ny cx cy hx hy k F hF)

sweepX-le : ∀ nx ny cx M F → Courant cx → OnGrid nx ny (_≤ M) F → OnGrid nx ny (_≤ M) (sweepX (suc nx) cx F)
sweepX-le nx ny cx M F hc hF x y hx hy =
  advect-le-max (suc nx) cx (F nx y) M (λ x′ → F x′ y) hc (hF nx y (n<1+n nx) hy) (λ i hi → hF i y hi hy) x hx

sweepY-le : ∀ nx ny cy M F → Courant cy → OnGrid nx ny (_≤ M) F → OnGrid nx ny (_≤ M) (sweepY (suc ny) cy F)
sweepY-le nx ny cy M F hc hF x y hx hy =
  advect-le-max (suc ny) cy (F x ny) M (λ y′ → F x y′) hc (hF x ny hx (n<1+n ny)) (λ j hj → hF x j hx hj) y hy

-- The maximum principle for every run length.
run2D-le : ∀ nx ny cx cy M → Courant cx → Courant cy → ∀ k F → OnGrid nx ny (_≤ M) F →
  OnGrid nx ny (_≤ M) (run2D (suc nx) (suc ny) cx cy k F)
run2D-le nx ny cx cy M hx hy zero    F hF = hF
run2D-le nx ny cx cy M hx hy (suc k) F hF =
  sweepY-le nx ny cy M _ hy (sweepX-le nx ny cx M _ hx (run2D-le nx ny cx cy M hx hy k F hF))

-- Stability in the maximum norm: a field in [0, M] stays in [0, M] for every number of steps.
run2D-bounded : ∀ nx ny cx cy M → Courant cx → Courant cy → ∀ k F →
  OnGrid nx ny (λ v → 0ℚ ≤ v × v ≤ M) F →
  OnGrid nx ny (λ v → 0ℚ ≤ v × v ≤ M) (run2D (suc nx) (suc ny) cx cy k F)
run2D-bounded nx ny cx cy M hx hy k F hF x y hxx hyy =
  run2D-nonneg nx ny cx cy hx hy k F (λ x y a b → proj₁ (hF x y a b)) x y hxx hyy ,
  run2D-le nx ny cx cy M hx hy k F (λ x y a b → proj₂ (hF x y a b)) x y hxx hyy
  where open import Data.Product using (proj₁; proj₂)
