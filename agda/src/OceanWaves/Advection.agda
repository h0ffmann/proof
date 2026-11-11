{-# OPTIONS --safe --without-K #-}

-- Propagation: first-order upwind advection in flux form. Ported from
-- `ocean-waves/lean/OceanWaves/Advection.lean`. The names follow Lean, with `-` for `_`.
--
-- One spectral component on a 1-D grid of n cells. The waves move in +x (c_g ≥ 0). Face i is
-- on the left of cell i, and face n is the right edge. `μ i = c_g(face i) Δt / Δx` is the
-- Courant number on face i.
--
--     F i  = μ i * N (i - 1)        (the upwind flux through face i; N (-1) = b)
--     N' i = N i + F i - F (i + 1)
--
-- b is the value that flows in on the left. A periodic grid uses b = N (n - 1).
--
-- This module proves:
--
-- * conservation: Σ N' = Σ N + F 0 - F n. On a periodic grid with one Courant number,
--   Σ N' = Σ N, for one step and for k steps;
-- * positivity under the CFL condition 0 ≤ μ ≤ 1, for one step and for k steps;
-- * the maximum principle for one Courant number: no new maximum.
--
-- Lean writes the upstream value with `if i = 0 then b else N (i - 1)`. Agda matches on i, so
-- each case reduces by computation.
module OceanWaves.Advection where

open import Data.Nat as ℕ using (ℕ; zero; suc; _∸_)
open import Data.Nat.Properties as ℕP using (n<1+n; <⇒≤)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Properties using (+-mono-≤; *-monoˡ-≤-nonNeg; ≤-trans; ≤-reflexive)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans)

open import OceanWaves.Sums

-- The value upstream of face i: the inflow b at face 0, else the cell on the left.
upstream : ℚ → (ℕ → ℚ) → ℕ → ℚ
upstream b N zero    = b
upstream b N (suc i) = N i

-- The upwind flux through face i.
upFlux : (ℕ → ℚ) → ℚ → (ℕ → ℚ) → ℕ → ℚ
upFlux μ b N i = μ i * upstream b N i

-- One upwind step.
advect : (ℕ → ℚ) → ℚ → (ℕ → ℚ) → ℕ → ℚ
advect μ b N i = N i + upFlux μ b N i - upFlux μ b N (suc i)

-- The step as a convex combination: N' i = (1 - μ (i + 1)) N i + μ i N (i - 1).
advect-eq : ∀ μ b N i → advect μ b N i ≡ (1ℚ - μ (suc i)) * N i + μ i * upstream b N i
advect-eq μ b N i =
  solve 3 (λ x u m → x :+ u :- m :* x := (con 1ℚ :- m) :* x :+ u) refl
    (N i) (upFlux μ b N i) (μ (suc i))

-- Conservation: the total changes only by the two boundary fluxes.
advect-sum : ∀ n μ b N → sumTo n (advect μ b N) ≡ sumTo n N + upFlux μ b N 0 - upFlux μ b N n
advect-sum zero μ b N =
  sym (solve 1 (λ f → con 0ℚ :+ f :- f := con 0ℚ) refl (upFlux μ b N 0))
advect-sum (suc n) μ b N
  rewrite advect-sum n μ b N =
    solve 5 (λ s f0 fn x fn1 → (s :+ f0 :- fn) :+ (x :+ fn :- fn1) := (s :+ x) :+ f0 :- fn1) refl
      (sumTo n N) (upFlux μ b N 0) (upFlux μ b N n) (N n) (upFlux μ b N (suc n))

-- One Courant number on every face.
constCourant : ℚ → ℕ → ℚ
constCourant c _ = c

-- Periodic boundary: what leaves on the right comes in on the left.
advectPeriodic : ℕ → ℚ → (ℕ → ℚ) → ℕ → ℚ
advectPeriodic n c N = advect (constCourant c) (N (n ∸ 1)) N

-- Exact conservation on a periodic grid of n + 1 cells (Lean: 0 < n).
advectPeriodic-sum : ∀ n c N → sumTo (suc n) (advectPeriodic (suc n) c N) ≡ sumTo (suc n) N
advectPeriodic-sum n c N =
  trans (advect-sum (suc n) (constCourant c) (N n) N)
    (solve 2 (λ s f → s :+ f :- f := s) refl (sumTo (suc n) N) (c * N n))

-- The CFL condition on the faces 0 … n.
CFL : ℕ → (ℕ → ℚ) → Set
CFL n μ = ∀ i → i ℕ.≤ n → 0ℚ ≤ μ i × μ i ≤ 1ℚ

private
  upstream-nonneg : ∀ {n b N} i → i ℕ.< n → 0ℚ ≤ b → (∀ j → j ℕ.< n → 0ℚ ≤ N j) →
                    0ℚ ≤ upstream b N i
  upstream-nonneg zero    _  hb hN = hb
  upstream-nonneg (suc i) hi hb hN = hN i (ℕP.<-trans (n<1+n i) hi)

  upstream-le : ∀ {n b M N} i → i ℕ.< n → b ≤ M → (∀ j → j ℕ.< n → N j ≤ M) →
                upstream b N i ≤ M
  upstream-le zero    _  hb hN = hb
  upstream-le (suc i) hi hb hN = hN i (ℕP.<-trans (n<1+n i) hi)

-- Positivity: under CFL, a non-negative field and inflow stay non-negative.
advect-nonneg : ∀ n μ b N → CFL n μ → 0ℚ ≤ b → (∀ i → i ℕ.< n → 0ℚ ≤ N i) →
                ∀ i → i ℕ.< n → 0ℚ ≤ advect μ b N i
advect-nonneg n μ b N hcfl hb hN i hi =
  ≤-trans
    (+-mono-≤ (*-nonneg (≤⇒0≤- (proj₂ (hcfl (suc i) hi))) (hN i hi))
              (*-nonneg (proj₁ (hcfl i (<⇒≤ hi))) (upstream-nonneg i hi hb hN)))
    (≤-reflexive (sym (advect-eq μ b N i)))

-- The maximum principle for one Courant number: when the field and the inflow are at most M,
-- the new field is at most M. (With a Courant number that changes from face to face this is
-- false in general: speeds that converge pile up action. That is shoaling, not an error.)
advect-le-max : ∀ n c b M N → 0ℚ ≤ c × c ≤ 1ℚ → b ≤ M → (∀ i → i ℕ.< n → N i ≤ M) →
                ∀ i → i ℕ.< n → advect (constCourant c) b N i ≤ M
advect-le-max n c b M N (c≥0 , c≤1) hb hN i hi =
  ≤-trans (≤-reflexive (advect-eq (constCourant c) b N i))
    (≤-trans
      (+-mono-≤ (*-monoˡ-≤-nonNeg (1ℚ - c) {{nonNegative (≤⇒0≤- c≤1)}} (hN i hi))
                (*-monoˡ-≤-nonNeg c {{nonNegative c≥0}} (upstream-le i hi hb hN)))
      (≤-reflexive (solve 2 (λ c m → (con 1ℚ :- c) :* m :+ c :* m := m) refl c M)))

-- k steps of periodic advection.
advectPeriodicN : ℕ → ℚ → ℕ → (ℕ → ℚ) → ℕ → ℚ
advectPeriodicN n c zero    N = N
advectPeriodicN n c (suc k) N = advectPeriodicN n c k (advectPeriodic n c N)

advectPeriodicN-sum : ∀ n c k N → sumTo (suc n) (advectPeriodicN (suc n) c k N) ≡ sumTo (suc n) N
advectPeriodicN-sum n c zero    N = refl
advectPeriodicN-sum n c (suc k) N =
  trans (advectPeriodicN-sum n c k (advectPeriodic (suc n) c N)) (advectPeriodic-sum n c N)

advectPeriodicN-nonneg : ∀ n c → 0ℚ ≤ c × c ≤ 1ℚ → ∀ k N → (∀ i → i ℕ.< suc n → 0ℚ ≤ N i) →
                         ∀ i → i ℕ.< suc n → 0ℚ ≤ advectPeriodicN (suc n) c k N i
advectPeriodicN-nonneg n c hc zero    N h = h
advectPeriodicN-nonneg n c hc (suc k) N h =
  advectPeriodicN-nonneg n c hc k (advectPeriodic (suc n) c N)
    (advect-nonneg (suc n) (constCourant c) (N n) N (λ _ _ → hc) (h n (n<1+n n)) h)
