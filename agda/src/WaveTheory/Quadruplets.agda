{-# OPTIONS --safe --without-K #-}

-- Four-wave (quadruplet) interactions on a discrete spectrum. New: the Lean original has only
-- the three-bin exchange `quad` of `OceanWaves.Sources`.
--
-- Hasselmann's nonlinear transfer in deep water moves action among four wave components that
-- meet the resonance conditions
--
--     k1 + k2 = k3 + k4,        σ1 + σ2 = σ3 + σ4.
--
-- One quartet with strength δ changes the four action densities by
--
--     δN1 = δN2 = δ,            δN3 = δN4 = -δ.
--
-- A spectrum here is a field N : ℕ → ℚ over bins 0 .. n - 1. Each bin has a frequency σ and
-- the two components kx, ky of its wavenumber. A list of quartets acts on the spectrum by the
-- sum of their indicators (`transfer`), as the edges of `WaveTheory.Unstructured` do.
--
-- For every weight w, the transfer changes Σ w N by exactly Σ_q δ (w1 + w2 - w3 - w4)
-- (`weighted-transfer`, `apply-weighted`), when every index of every quartet is below n. So:
--
-- * the total action is kept for every list of quartets (`apply-action`);
-- * the total energy Σ σ N is kept when every quartet meets the frequency resonance
--   (`apply-energy`);
-- * the total momentum Σ kx N and Σ ky N is kept when every quartet meets the wavenumber
--   resonance (`apply-momentum`).
--
-- The quartet shape of the Discrete Interaction Approximation (DIA, Hasselmann et al. 1985,
-- doi:10.1175/1520-0485(1985)015<1378:CAPOTN>2.0.CO;2), σ, σ, σ(1 + λ), σ(1 - λ), meets the
-- frequency resonance (`dia-quartet-resonant`). A quartet that does not meet it changes the
-- energy by exactly δ (σ1 + σ2 - σ3 - σ4) (`off-resonance-energy`), and the examples show one
-- such change that is not zero.
--
-- Limits: δ is any rational. Nothing here computes δ from the Boltzmann integral, and the
-- wavenumber resonance of the DIA (which needs angles) is a premise, not a theorem. The bins
-- are the same weights for energy and momentum; a bin width (a quadrature weight) is not
-- modelled.
module WaveTheory.Quadruplets where

open import Data.Bool using (true; false)
open import Data.List using (List; []; _∷_)
open import Data.Unit using (⊤; tt)
open import Data.Product using (_×_; _,_)
open import Data.Nat as ℕ using (ℕ; zero; suc)
import Data.Integer as ℤ
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _/_; -_)
open import Data.Rational.Properties using (*-zeroʳ; *-identityˡ; +-identityʳ)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂)

open import OceanWaves.Sums
open import OceanWaves.Sources using (dia-resonance)

-- One quartet: two bins that gain, two bins that lose, and the strength δ.
record Quartet : Set where
  constructor quartet
  field
    i1 i2 i3 i4 : ℕ
    δ           : ℚ
open Quartet public

-- What one quartet adds to bin j. Two indices may be the same bin (the DIA has i1 = i2).
gain : Quartet → ℕ → ℚ
gain q j = pick (i1 q) (λ _ → δ q) j + pick (i2 q) (λ _ → δ q) j
         - pick (i3 q) (λ _ → δ q) j - pick (i4 q) (λ _ → δ q) j

-- The net transfer of a list of quartets to bin j.
transfer : List Quartet → ℕ → ℚ
transfer []       j = 0ℚ
transfer (q ∷ qs) j = gain q j + transfer qs j

-- The spectrum after the transfer.
apply : List Quartet → (ℕ → ℚ) → ℕ → ℚ
apply Q N j = N j + transfer Q j

-- What one quartet does to Σ w N.
quartetBudget : (ℕ → ℚ) → Quartet → ℚ
quartetBudget w q = δ q * (w (i1 q) + w (i2 q) - w (i3 q) - w (i4 q))

budget : (ℕ → ℚ) → List Quartet → ℚ
budget w []       = 0ℚ
budget w (q ∷ qs) = quartetBudget w q + budget w qs

-- Every index of every quartet is a bin below n.
InSpectrum : ℕ → List Quartet → Set
InSpectrum n []       = ⊤
InSpectrum n (q ∷ qs) =
  (i1 q ℕ.< n) × (i2 q ℕ.< n) × (i3 q ℕ.< n) × (i4 q ℕ.< n) × InSpectrum n qs

-- Every quartet meets w1 + w2 = w3 + w4: the frequency resonance for w = σ, a wavenumber
-- component of the momentum resonance for w = kx or w = ky.
Resonant : (ℕ → ℚ) → List Quartet → Set
Resonant w []       = ⊤
Resonant w (q ∷ qs) = (w (i1 q) + w (i2 q) ≡ w (i3 q) + w (i4 q)) × Resonant w qs

-- ---------------------------------------------------------------------------------------------
-- The weighted budget

private
  pick-weight : ∀ a c (w : ℕ → ℚ) j → w j * pick a (λ _ → c) j ≡ pick a (λ k → w k * c) j
  pick-weight a c w j with j ℕ.≡ᵇ a
  ... | true  = refl
  ... | false = *-zeroʳ (w j)

-- For every weight w, the transfer changes Σ w N by the budget of its quartets.
weighted-transfer : ∀ n (w : ℕ → ℚ) Q → InSpectrum n Q →
  sumTo n (λ j → w j * transfer Q j) ≡ budget w Q
weighted-transfer n w []       _ = trans (sumTo-congr n _ _ (λ j _ → *-zeroʳ (w j))) (sumTo-zero-fn n)
weighted-transfer n w (q ∷ qs) (h1 , h2 , h3 , h4 , hs) =
  trans (sumTo-congr n _ _ (λ j _ → split j))
  (trans (sumTo-add n (λ j → ((P1 j + P2 j) - P3 j) - P4 j) (λ j → w j * transfer qs j))
  (cong₂ _+_ one (weighted-transfer n w qs hs)))
  where
  P : ℕ → ℕ → ℚ
  P a = pick a (λ k → w k * δ q)
  P1 = P (i1 q)
  P2 = P (i2 q)
  P3 = P (i3 q)
  P4 = P (i4 q)
  p : ℕ → ℕ → ℚ
  p a = pick a (λ _ → δ q)

  split : ∀ j → w j * transfer (q ∷ qs) j ≡ ((P1 j + P2 j) - P3 j) - P4 j + w j * transfer qs j
  split j =
    trans (solve 6 (λ x a b c d t → x :* ((a :+ b :- c :- d) :+ t)
                     := x :* a :+ x :* b :- x :* c :- x :* d :+ x :* t) refl
             (w j) (p (i1 q) j) (p (i2 q) j) (p (i3 q) j) (p (i4 q) j) (transfer qs j))
          (cong (_+ w j * transfer qs j)
            (cong₂ _-_ (cong₂ _-_ (cong₂ _+_ (pick-weight (i1 q) (δ q) w j)
                                             (pick-weight (i2 q) (δ q) w j))
                                  (pick-weight (i3 q) (δ q) w j))
                       (pick-weight (i4 q) (δ q) w j)))

  one : sumTo n (λ j → ((P1 j + P2 j) - P3 j) - P4 j) ≡ quartetBudget w q
  one =
    trans (sumTo-sub n (λ j → (P1 j + P2 j) - P3 j) P4)
    (trans (cong (_- sumTo n P4) (sumTo-sub n (λ j → P1 j + P2 j) P3))
    (trans (cong (λ s → s - sumTo n P3 - sumTo n P4) (sumTo-add n P1 P2))
    (trans (cong₂ (λ a b → a - b) (cong₂ (λ a b → a - b)
             (cong₂ _+_ (sumTo-pick n (i1 q) _ h1) (sumTo-pick n (i2 q) _ h2))
             (sumTo-pick n (i3 q) _ h3))
             (sumTo-pick n (i4 q) _ h4))
           (solve 5 (λ a b c d e → a :* e :+ b :* e :- c :* e :- d :* e
                       := e :* (a :+ b :- c :- d)) refl
              (w (i1 q)) (w (i2 q)) (w (i3 q)) (w (i4 q)) (δ q)))))

-- The same budget, for the spectrum after the transfer.
apply-weighted : ∀ n (w N : ℕ → ℚ) Q → InSpectrum n Q →
  sumTo n (λ j → w j * apply Q N j) ≡ sumTo n (λ j → w j * N j) + budget w Q
apply-weighted n w N Q h =
  trans (sumTo-congr n _ _ (λ j _ →
           solve 3 (λ x a t → x :* (a :+ t) := x :* a :+ x :* t) refl (w j) (N j) (transfer Q j)))
  (trans (sumTo-add n (λ j → w j * N j) (λ j → w j * transfer Q j))
         (cong (sumTo n (λ j → w j * N j) +_) (weighted-transfer n w Q h)))

-- A resonant list of quartets has a zero budget.
budget-zero : ∀ (w : ℕ → ℚ) Q → Resonant w Q → budget w Q ≡ 0ℚ
budget-zero w []       _        = refl
budget-zero w (q ∷ qs) (r , rs) =
  trans (cong₂ _+_ one (budget-zero w qs rs)) (+-identityʳ 0ℚ)
  where
  one : quartetBudget w q ≡ 0ℚ
  one = trans (cong (λ x → δ q * (x - w (i3 q) - w (i4 q))) r)
              (solve 3 (λ e c d → e :* (c :+ d :- c :- d) := con 0ℚ) refl
                 (δ q) (w (i3 q)) (w (i4 q)))

-- A weight that every quartet meets is kept by the transfer.
apply-kept : ∀ n (w N : ℕ → ℚ) Q → InSpectrum n Q → Resonant w Q →
  sumTo n (λ j → w j * apply Q N j) ≡ sumTo n (λ j → w j * N j)
apply-kept n w N Q h r =
  trans (apply-weighted n w N Q h)
        (trans (cong (sumTo n (λ j → w j * N j) +_) (budget-zero w Q r))
               (+-identityʳ (sumTo n (λ j → w j * N j))))

-- ---------------------------------------------------------------------------------------------
-- Action, energy and momentum

-- Every quartet gains two units and loses two, so the weight 1 is always resonant.
private
  one-resonant : ∀ Q → Resonant (λ _ → 1ℚ) Q
  one-resonant []       = tt
  one-resonant (q ∷ qs) = refl , one-resonant qs

-- The net transfer of action is zero.
transfer-action : ∀ n Q → InSpectrum n Q → sumTo n (transfer Q) ≡ 0ℚ
transfer-action n Q h =
  trans (sumTo-congr n _ _ (λ j _ → sym (*-identityˡ (transfer Q j))))
        (trans (weighted-transfer n (λ _ → 1ℚ) Q h) (budget-zero (λ _ → 1ℚ) Q (one-resonant Q)))

-- The total action is kept, for every list of quartets.
apply-action : ∀ n N Q → InSpectrum n Q → sumTo n (apply Q N) ≡ sumTo n N
apply-action n N Q h =
  trans (sumTo-add n N (transfer Q))
        (trans (cong (sumTo n N +_) (transfer-action n Q h)) (+-identityʳ (sumTo n N)))

-- The total energy Σ σ N is kept when every quartet meets σ1 + σ2 = σ3 + σ4.
apply-energy : ∀ n (σ N : ℕ → ℚ) Q → InSpectrum n Q → Resonant σ Q →
  sumTo n (λ j → σ j * apply Q N j) ≡ sumTo n (λ j → σ j * N j)
apply-energy = apply-kept

-- The total momentum is kept when every quartet meets k1 + k2 = k3 + k4 in both components.
apply-momentum : ∀ n (kx ky N : ℕ → ℚ) Q → InSpectrum n Q → Resonant kx Q → Resonant ky Q →
  sumTo n (λ j → kx j * apply Q N j) ≡ sumTo n (λ j → kx j * N j)
  × sumTo n (λ j → ky j * apply Q N j) ≡ sumTo n (λ j → ky j * N j)
apply-momentum n kx ky N Q h rx ry = apply-kept n kx N Q h rx , apply-kept n ky N Q h ry

-- A quartet off the frequency resonance changes the energy by exactly δ (σ1 + σ2 - σ3 - σ4).
off-resonance-energy : ∀ n (σ N : ℕ → ℚ) q → InSpectrum n (q ∷ []) →
  sumTo n (λ j → σ j * apply (q ∷ []) N j)
    ≡ sumTo n (λ j → σ j * N j) + δ q * (σ (i1 q) + σ (i2 q) - σ (i3 q) - σ (i4 q))
off-resonance-energy n σ N q h =
  trans (apply-weighted n σ N (q ∷ []) h)
        (cong (sumTo n (λ j → σ j * N j) +_) (+-identityʳ (quartetBudget σ q)))

-- The DIA quartet: σ at i1 and i2, σ (1 + λ) at i3, σ (1 - λ) at i4. It meets the frequency
-- resonance for every σ and λ.
dia-quartet-resonant : ∀ (σ : ℕ → ℚ) s lam q →
  σ (i1 q) ≡ s → σ (i2 q) ≡ s → σ (i3 q) ≡ s * (1ℚ + lam) → σ (i4 q) ≡ s * (1ℚ - lam) →
  Resonant σ (q ∷ [])
dia-quartet-resonant σ s lam q e1 e2 e3 e4 =
  trans (cong₂ _+_ e1 e2) (trans (dia-resonance s lam) (sym (cong₂ _+_ e3 e4))) , tt

-- ---------------------------------------------------------------------------------------------
-- Examples

private
  ¾ ¼ ⁵⁄₄ : ℚ
  ¾   = ℤ.+ 3 / 4
  ¼   = ℤ.+ 1 / 4
  ⁵⁄₄ = ℤ.+ 5 / 4

-- Three bins with σ = 3/4, 1, 5/4: the DIA shape with σ = 1 and λ = 1/4.
σex : ℕ → ℚ
σex 0 = ¾
σex 1 = 1ℚ
σex _ = ⁵⁄₄

-- Bin 1 gains twice, bins 2 and 0 lose once each.
diaQ : Quartet
diaQ = quartet 1 1 2 0 ¼

diaQ-in : InSpectrum 3 (diaQ ∷ [])
diaQ-in = ℕ.s≤s (ℕ.s≤s ℕ.z≤n) , ℕ.s≤s (ℕ.s≤s ℕ.z≤n) , ℕ.s≤s (ℕ.s≤s (ℕ.s≤s ℕ.z≤n))
        , ℕ.s≤s ℕ.z≤n , tt

ex-dia-resonant : Resonant σex (diaQ ∷ [])
ex-dia-resonant = dia-quartet-resonant σex 1ℚ ¼ diaQ refl refl refl refl

ex-transfer : transfer (diaQ ∷ []) 0 ≡ - ¼ × transfer (diaQ ∷ []) 1 ≡ ℤ.+ 1 / 2
            × transfer (diaQ ∷ []) 2 ≡ - ¼
ex-transfer = refl , refl , refl

ex-action : sumTo 3 (transfer (diaQ ∷ [])) ≡ 0ℚ
ex-action = refl

ex-energy : sumTo 3 (λ j → σex j * transfer (diaQ ∷ []) j) ≡ 0ℚ
ex-energy = refl

-- Off resonance: bin 0 gains twice, bins 1 and 2 lose. σ1 + σ2 - σ3 - σ4 = 3/2 - 9/4 = -3/4,
-- so with δ = 1/4 the energy falls by 3/16 while the action is kept.
offQ : Quartet
offQ = quartet 0 0 1 2 ¼

ex-off-action : sumTo 3 (transfer (offQ ∷ [])) ≡ 0ℚ
ex-off-action = refl

ex-off-energy : sumTo 3 (λ j → σex j * transfer (offQ ∷ []) j) ≡ ℤ.-[1+ 2 ] / 16
ex-off-energy = refl
