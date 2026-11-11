{-# OPTIONS --safe --without-K #-}

-- The model's time loop: many steps of `OceanWaves.ActionBalance.step`, and what stays true
-- for every run length. New: the Lean original proves one step only.
--
-- One step propagates every spectral bin (upwind, periodic, the depth CFL) and then applies
-- the sources (semi-implicit wind input and whitecapping, the limited quadruplet transfer).
-- For a run of k steps:
--
--   - the spectrum stays non-negative, for every Δt (`run-nonneg`);
--   - when whitecapping is at least the wind input in every bin, the total action never
--     grows (`run-total-le`): the loop is stable in the ℓ¹ norm, which is the action norm;
--   - when the wind input is at most B, the total action grows at most by (1 + Δt B) per step
--     (`run-total-growth`), a discrete Grönwall bound.
--
-- The two total-action results need the limiter to be inactive (`Free`) on the fields the
-- run visits; they assume it step by step, on the run itself, and do not claim it for every
-- field.
module WaveTheory.TimeLoop where

open import Data.Nat as ℕ using (ℕ; zero; suc)
import Data.Nat.Properties as ℕP
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; _≤_; _<_)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; <⇒≤; +-monoʳ-≤; *-monoˡ-≤-nonNeg; *-monoʳ-≤-nonNeg)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong)

open import OceanWaves.Order
open import OceanWaves.Sums
open import OceanWaves.Sources
open import OceanWaves.ActionBalance
open import WaveTheory.Algebra

-- ---------------------------------------------------------------------------------------------
-- The semi-implicit source step, bounded

-- When whitecapping is at least the input, the semi-implicit step does not grow N.
linStep-le : ∀ {Δt β γ N} → 0ℚ ≤ Δt → 0ℚ ≤ β → β ≤ γ → 0ℚ ≤ N → linStep Δt β γ N ≤ N
linStep-le {Δt} {β} {γ} {N} ht hβ hβγ hN =
  div-le-of-le-mul {a = N * (1ℚ + Δt * β)} {b = 1ℚ + Δt * γ} {c = N}
    (+-pos 0<1 (*-nonneg ht (≤-trans hβ hβγ)))
    (*-monoˡ-≤-nonNeg N {{nonNegative hN}} (+-monoʳ-≤ 1ℚ (*-monoˡ-≤-nonNeg Δt {{nonNegative ht}} hβγ)))

-- When the input is at most B, the semi-implicit step grows N by at most 1 + Δt B.
linStep-le-growth : ∀ {Δt β γ N} B → 0ℚ ≤ Δt → 0ℚ ≤ β → β ≤ B → 0ℚ ≤ γ → 0ℚ ≤ N →
  linStep Δt β γ N ≤ (1ℚ + Δt * B) * N
linStep-le-growth {Δt} {β} {γ} {N} B ht hβ hβB hγ hN =
  div-le-of-le-mul {a = N * (1ℚ + Δt * β)} {b = 1ℚ + Δt * γ} {c = (1ℚ + Δt * B) * N}
    (+-pos 0<1 (*-nonneg ht hγ))
    (by-diff (N * (Δt * (B - β)) + (1ℚ + Δt * B) * N * (Δt * γ))
       (solve 5 (λ n t b β g →
          (con 1ℚ :+ t :* b) :* n :* (con 1ℚ :+ t :* g) :- n :* (con 1ℚ :+ t :* β)
          := n :* (t :* (b :- β)) :+ (con 1ℚ :+ t :* b) :* n :* (t :* g)) refl N Δt B β γ)
       (+-nonneg (*-nonneg hN (*-nonneg ht (≤⇒0≤- hβB)))
                 (*-nonneg (*-nonneg (+-nonneg (<⇒≤ 0<1) (*-nonneg ht (≤-trans hβ hβB))) hN)
                           (*-nonneg ht hγ))))

-- ---------------------------------------------------------------------------------------------
-- The run

module _ (C : StepConfig) where
  open StepConfig C

  -- k model steps.
  run : ℕ → (ℕ → ℕ → ℚ) → ℕ → ℕ → ℚ
  run zero    F = F
  run (suc k) F = step C (run k F)

  -- The spectrum stays non-negative for every run length and every Δt: the source step clips
  -- at -N*, and N* ≥ 0.
  run-nonneg : ∀ k F → (∀ x j → 0ℚ ≤ F x j) → ∀ x j → 0ℚ ≤ run k F x j
  run-nonneg zero    F hF = hF
  run-nonneg (suc k) F hF = step-nonneg C (run k F)

  -- The limiter does not clip anywhere in the step from F.
  Free : (ℕ → ℕ → ℚ) → Set
  Free F = ∀ x → x ℕ.< nx → ∀ j → j ℕ.< nb →
    - linStep Δt (β (P x) j) (γ (P x) j) (P x j) ≤ Δt * snl nb (d (P x)) j
    × Δt * snl nb (d (P x)) j ≤ L
    where P = propagate C F

  -- Whitecapping is at least the wind input in every bin, after propagation.
  Dissipative : (ℕ → ℕ → ℚ) → Set
  Dissipative F = ∀ x → x ℕ.< nx → ∀ j → j ℕ.< nb → 0ℚ ≤ β (P x) j × β (P x) j ≤ γ (P x) j
    where P = propagate C F

  -- The wind input is in [0, B] and whitecapping is non-negative, after propagation.
  InputBelow : ℚ → (ℕ → ℕ → ℚ) → Set
  InputBelow B F = ∀ x → x ℕ.< nx → ∀ j → j ℕ.< nb →
    0ℚ ≤ β (P x) j × β (P x) j ≤ B × 0ℚ ≤ γ (P x) j
    where P = propagate C F

  module _ (hC : Valid C) where
    open Valid hC

    private
      P-nonneg : ∀ F → (∀ x j → 0ℚ ≤ F x j) → ∀ x j → x ℕ.< nx → 0ℚ ≤ propagate C F x j
      P-nonneg F hF = propagate-nonneg C hC F (λ x j _ → hF x j)

    -- One dissipative step does not grow the total action.
    step-total-le : ∀ F → (∀ x j → 0ℚ ≤ F x j) → Free F → Dissipative F →
      totalAction C (step C F) ≤ totalAction C F
    step-total-le F hF hfree hdis =
      ≤-trans (≤-reflexive (step-total C F hfree))
      (≤-trans (sumTo-mono nx _ _ (λ x hx → sumTo-mono nb _ _ (λ j hj →
                  linStep-le Δt-nonneg (proj₁ (hdis x hx j hj)) (proj₂ (hdis x hx j hj)) (P-nonneg F hF x j hx))))
               (≤-reflexive (propagate-total C hC F)))

    -- Stability of the loop in the action norm: a dissipative run never gains action.
    run-total-le : ∀ k F → (∀ x j → 0ℚ ≤ F x j) →
      (∀ i → i ℕ.< k → Free (run i F) × Dissipative (run i F)) →
      totalAction C (run k F) ≤ totalAction C F
    run-total-le zero    F hF h = ≤-refl
    run-total-le (suc k) F hF h =
      ≤-trans (step-total-le (run k F) (run-nonneg k F hF) (proj₁ (h k (ℕP.n<1+n k))) (proj₂ (h k (ℕP.n<1+n k))))
              (run-total-le k F hF (λ i hi → h i (ℕP.m<n⇒m<1+n hi)))

    -- With the wind input at most B, one step grows the total action by at most 1 + Δt B.
    step-total-growth : ∀ B F → (∀ x j → 0ℚ ≤ F x j) → Free F → InputBelow B F →
      totalAction C (step C F) ≤ (1ℚ + Δt * B) * totalAction C F
    step-total-growth B F hF hfree hin =
      ≤-trans (≤-reflexive (step-total C F hfree))
      (≤-trans (sumTo-mono nx _ _ (λ x hx → sumTo-mono nb _ _ (λ j hj →
                  linStep-le-growth B Δt-nonneg (proj₁ (hin x hx j hj)) (proj₁ (proj₂ (hin x hx j hj)))
                    (proj₂ (proj₂ (hin x hx j hj))) (P-nonneg F hF x j hx))))
      (≤-trans (≤-reflexive (trans (sumTo-congr nx _ _ (λ x _ → sumTo-mul-left nb r (propagate C F x)))
                                   (sumTo-mul-left nx r (λ x → sumTo nb (propagate C F x)))))
               (≤-reflexive (cong (r *_) (propagate-total C hC F)))))
      where r = 1ℚ + Δt * B

    -- The discrete Grönwall bound for the run: total(k) ≤ (1 + Δt B)^k total(0).
    run-total-growth : ∀ B → 0ℚ ≤ B → ∀ k F → (∀ x j → 0ℚ ≤ F x j) →
      (∀ i → i ℕ.< k → Free (run i F) × InputBelow B (run i F)) →
      totalAction C (run k F) ≤ pow (1ℚ + Δt * B) k * totalAction C F
    run-total-growth B hB zero    F hF h =
      ≤-reflexive (sym (solve 1 (λ t → con 1ℚ :* t := t) refl (totalAction C F)))
    run-total-growth B hB (suc k) F hF h =
      ≤-trans (step-total-growth B (run k F) (run-nonneg k F hF) (proj₁ (h k (ℕP.n<1+n k))) (proj₂ (h k (ℕP.n<1+n k))))
      (≤-trans (*-monoˡ-≤-nonNeg r {{nonNegative (+-nonneg (<⇒≤ 0<1) (*-nonneg Δt-nonneg hB))}}
                  (run-total-growth B hB k F hF (λ i hi → h i (ℕP.m<n⇒m<1+n hi))))
               (≤-reflexive (solve 3 (λ r p t → r :* (p :* t) := r :* p :* t) refl r (pow r k) (totalAction C F))))
      where r = 1ℚ + Δt * B
