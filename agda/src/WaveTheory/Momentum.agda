{-# OPTIONS --safe --without-K #-}

-- The momentum (pseudo-momentum) of a linear wave train, and the Stokes drift. New: the Lean
-- original has no wave momentum.
--
-- A wave train of energy E (per unit area, in units with ρ g = 1), radian frequency σ and
-- wavenumber k carries the wave action N = E / σ and the momentum
--
--     M = E k / σ = k N,
--
-- so the momentum is the wavenumber times the action (Andrews and McIntyre, 1978). With the
-- phase speed c = σ / k this is M = E / c. The mass transport of the Stokes drift is M, and
-- its volume transport is M / ρ. In deep water
-- the Stokes drift at the surface is u_s = σ k a², and with E = a² / 2 this is u_s = 2 σ k E
-- (Stokes, 1847; Phillips, 1977, "The dynamics of the upper ocean").
--
-- ℚ has no square root and no cosine. So σ, k, E, ρ and g are free rationals with sign or
-- non-zero premises, the deep-water dispersion relation is stated squared (σ² = g k), and the
-- direction is a rational unit vector, the `Direction` of `WaveTheory.RadiationStress`.
--
-- What this module proves:
--
-- * M = k N (`momentum-kN`), M c = E for k ≠ 0 and σ ≠ 0 (`momentum-times-phase`), and M ≥ 0
--   for E ≥ 0, k ≥ 0, σ > 0 (`momentum-nonneg`);
-- * in deep water (n = 1/2) at normal incidence, S_xx = E/2 = M c_g with c_g = c / 2
--   (`Sxx-deep-momentum-flux`): the radiation stress is the momentum times the speed that
--   carries it;
-- * the momentum vector (M cos θ, M sin θ) has the squared length M² (`momentum-vector-norm`);
-- * the momentum of a discrete spectrum Σ k_i N_i is additive in the action and non-negative
--   (`spectrum-momentum-add`, `spectrum-momentum-nonneg`);
-- * with σ² = g k, M g = E σ (`momentum-deep`), so M = E σ / g;
-- * the Stokes volume transport M / ρ gives back M when multiplied by ρ ≠ 0;
-- * the deep-water surface Stokes drift u_s = 2 σ k E equals σ k a² when a² = 2 E, is
--   non-negative and grows with E (`stokes-amplitude`, `stokes-nonneg`, `stokes-mono`).
module WaveTheory.Momentum where

open import Data.Nat as ℕ using (ℕ)
open import Data.Integer using (+_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _<_; _/_)
open import Data.Rational.Properties using (<⇒≤; *-identityʳ)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong)

open import OceanWaves.Order
open import OceanWaves.Sums
open import WaveTheory.RadiationStress using (Direction; cs; sn; unit; normal; ½; Sxx; Sxx-normal-deep)

-- ---------------------------------------------------------------------------------------------
-- Action, momentum and phase speed

action : ℚ → ℚ → ℚ
action E σ = E /₀ σ

momentum : ℚ → ℚ → ℚ → ℚ
momentum E σ k = E * k /₀ σ

phase : ℚ → ℚ → ℚ
phase σ k = σ /₀ k

-- M = k N, with no premise: both sides use the same total inverse of σ.
momentum-kN : ∀ E σ k → momentum E σ k ≡ k * action E σ
momentum-kN E σ k = solve 3 (λ E k i → E :* k :* i := k :* (E :* i)) refl E k (inv₀ σ)

-- M c = E: the momentum is the energy divided by the phase speed.
momentum-times-phase : ∀ E σ k → σ ≢ 0ℚ → k ≢ 0ℚ → momentum E σ k * phase σ k ≡ E
momentum-times-phase E σ k hσ hk =
  trans (solve 5 (λ E σ k i j → E :* k :* i :* (σ :* j) := E :* (σ :* i) :* (k :* j))
           refl E σ k (inv₀ σ) (inv₀ k))
  (trans (cong (λ t → E * t * (k * inv₀ k)) (inv₀-inverse σ hσ))
  (trans (cong (λ t → E * 1ℚ * t) (inv₀-inverse k hk))
         (solve 1 (λ E → E :* con 1ℚ :* con 1ℚ := E) refl E)))

momentum-nonneg : ∀ {E σ k} → 0ℚ ≤ E → 0ℚ ≤ k → 0ℚ < σ → 0ℚ ≤ momentum E σ k
momentum-nonneg hE hk hσ = div-nonneg (*-nonneg hE hk) (<⇒≤ hσ)

-- ---------------------------------------------------------------------------------------------
-- Momentum flux and radiation stress in deep water

-- The deep-water group speed: half the phase speed.
cg-deep : ℚ → ℚ → ℚ
cg-deep σ k = phase σ k * ½

-- At normal incidence in deep water, S_xx = E/2 = M c_g.
Sxx-deep-momentum-flux : ∀ E σ k → σ ≢ 0ℚ → k ≢ 0ℚ →
  Sxx E ½ normal ≡ momentum E σ k * cg-deep σ k
Sxx-deep-momentum-flux E σ k hσ hk =
  trans (Sxx-normal-deep E)
  (sym (trans (solve 3 (λ m c h → m :* (c :* h) := m :* c :* h) refl (momentum E σ k) (phase σ k) ½)
              (cong (_* ½) (momentum-times-phase E σ k hσ hk))))

-- ---------------------------------------------------------------------------------------------
-- The momentum vector

module _ (M : ℚ) (d : Direction) where
  Mx My : ℚ
  Mx = M * cs d
  My = M * sn d

  -- The vector has the length of M, because the direction is a unit vector.
  momentum-vector-norm : Mx * Mx + My * My ≡ M * M
  momentum-vector-norm =
    trans (solve 3 (λ M c s → M :* c :* (M :* c) :+ M :* s :* (M :* s) := M :* M :* (c :* c :+ s :* s))
             refl M (cs d) (sn d))
    (trans (cong (M * M *_) (unit d)) (*-identityʳ (M * M)))

-- ---------------------------------------------------------------------------------------------
-- A discrete spectrum

-- Σ k_i N_i over n components.
spectrum-momentum : ℕ → (ℕ → ℚ) → (ℕ → ℚ) → ℚ
spectrum-momentum n k N = sumTo n (λ i → k i * N i)

-- The sum of the component momenta E_i k_i / σ_i is Σ k_i N_i.
spectrum-momentum-components : ∀ n (E σ k : ℕ → ℚ) →
  sumTo n (λ i → momentum (E i) (σ i) (k i)) ≡ spectrum-momentum n k (λ i → action (E i) (σ i))
spectrum-momentum-components n E σ k =
  sumTo-congr n _ _ (λ i _ → momentum-kN (E i) (σ i) (k i))

-- Additive in the action: two wave fields on the same wavenumbers add their momenta.
spectrum-momentum-add : ∀ n (k N₁ N₂ : ℕ → ℚ) →
  spectrum-momentum n k (λ i → N₁ i + N₂ i) ≡ spectrum-momentum n k N₁ + spectrum-momentum n k N₂
spectrum-momentum-add n k N₁ N₂ =
  trans (sumTo-congr n _ _ (λ i _ → solve 3 (λ k a b → k :* (a :+ b) := k :* a :+ k :* b) refl (k i) (N₁ i) (N₂ i)))
        (sumTo-add n (λ i → k i * N₁ i) (λ i → k i * N₂ i))

spectrum-momentum-nonneg : ∀ n (k N : ℕ → ℚ) →
  (∀ i → i ℕ.< n → 0ℚ ≤ k i) → (∀ i → i ℕ.< n → 0ℚ ≤ N i) → 0ℚ ≤ spectrum-momentum n k N
spectrum-momentum-nonneg n k N hk hN =
  sumTo-nonneg n _ (λ i i<n → *-nonneg (hk i i<n) (hN i i<n))

-- ---------------------------------------------------------------------------------------------
-- Deep water: σ² = g k gives M g = E σ, so M = E σ / g

momentum-deep : ∀ E σ k g → σ ≢ 0ℚ → σ * σ ≡ g * k → momentum E σ k * g ≡ E * σ
momentum-deep E σ k g hσ disp =
  trans (solve 4 (λ E k g i → E :* k :* i :* g := E :* (g :* k) :* i) refl E k g (inv₀ σ))
  (trans (cong (λ t → E * t * inv₀ σ) (sym disp))
  (trans (solve 3 (λ E σ i → E :* (σ :* σ) :* i := E :* σ :* (σ :* i)) refl E σ (inv₀ σ))
  (trans (cong (E * σ *_) (inv₀-inverse σ hσ)) (*-identityʳ (E * σ)))))

-- ---------------------------------------------------------------------------------------------
-- The Stokes drift

-- The volume transport of the Stokes drift: M / ρ.
stokes-transport : ℚ → ℚ → ℚ → ℚ → ℚ
stokes-transport ρ E σ k = momentum E σ k /₀ ρ

stokes-transport-mass : ∀ ρ E σ k → ρ ≢ 0ℚ → stokes-transport ρ E σ k * ρ ≡ momentum E σ k
stokes-transport-mass ρ E σ k hρ = div-mul-cancel (momentum E σ k) hρ

stokes-transport-nonneg : ∀ {ρ E σ k} → 0ℚ < ρ → 0ℚ ≤ E → 0ℚ ≤ k → 0ℚ < σ →
  0ℚ ≤ stokes-transport ρ E σ k
stokes-transport-nonneg hρ hE hk hσ = div-nonneg (momentum-nonneg hE hk hσ) (<⇒≤ hρ)

-- The deep-water surface Stokes drift u_s = 2 σ k E (E = a² / 2, units with ρ g = 1).
stokes : ℚ → ℚ → ℚ → ℚ
stokes σ k E = 2ℚ * σ * k * E

-- With a² = 2 E this is σ k a².
stokes-amplitude : ∀ σ k E a → a * a ≡ 2ℚ * E → stokes σ k E ≡ σ * k * (a * a)
stokes-amplitude σ k E a ha =
  trans (solve 3 (λ σ k E → (con 1ℚ :+ con 1ℚ) :* σ :* k :* E := σ :* k :* ((con 1ℚ :+ con 1ℚ) :* E)) refl σ k E)
        (cong (σ * k *_) (sym ha))

stokes-nonneg : ∀ {σ k E} → 0ℚ ≤ σ → 0ℚ ≤ k → 0ℚ ≤ E → 0ℚ ≤ stokes σ k E
stokes-nonneg hσ hk hE = *-nonneg (*-nonneg (*-nonneg (<⇒≤ 0<2) hσ) hk) hE

stokes-mono : ∀ {σ k E₁ E₂} → 0ℚ ≤ σ → 0ℚ ≤ k → E₁ ≤ E₂ → stokes σ k E₁ ≤ stokes σ k E₂
stokes-mono {σ} {k} {E₁} {E₂} hσ hk hE =
  by-diff (2ℚ * σ * k * (E₂ - E₁))
    (solve 4 (λ σ k a b → (con 1ℚ :+ con 1ℚ) :* σ :* k :* b :- (con 1ℚ :+ con 1ℚ) :* σ :* k :* a
                        := (con 1ℚ :+ con 1ℚ) :* σ :* k :* (b :- a)) refl σ k E₁ E₂)
    (*-nonneg (*-nonneg (*-nonneg (<⇒≤ 0<2) hσ) hk) (≤⇒0≤- hE))

-- ---------------------------------------------------------------------------------------------
-- Examples

-- E = 1, σ = 2, k = 4: N = 1/2, M = 2, c = 1/2 and M c = 1 = E.
ex-momentum : momentum 1ℚ (lit 2) (lit 4) ≡ lit 2
ex-momentum = refl

ex-action : action 1ℚ (lit 2) ≡ + 1 / 2
ex-action = refl

ex-times-phase : momentum 1ℚ (lit 2) (lit 4) * phase (lit 2) (lit 4) ≡ 1ℚ
ex-times-phase = refl

-- Deep water with g = 10, σ = 2, k = 2/5 (σ² = g k = 4), E = 3: M = 3/5 and M g = 6 = E σ.
ex-deep-disp : lit 2 * lit 2 ≡ lit 10 * (+ 2 / 5)
ex-deep-disp = refl

ex-deep : momentum (lit 3) (lit 2) (+ 2 / 5) * lit 10 ≡ lit 3 * lit 2
ex-deep = refl

-- S_xx = E/2 = M c_g for E = 1, σ = 2, k = 4.
ex-Sxx : Sxx 1ℚ ½ normal ≡ momentum 1ℚ (lit 2) (lit 4) * cg-deep (lit 2) (lit 4)
ex-Sxx = refl

-- A two-component spectrum: k = (1, 2), N = (3, 1/2) gives Σ k N = 4.
ex-spectrum : spectrum-momentum 2 (λ i → lit (ℕ.suc i)) (λ { 0 → lit 3 ; _ → + 1 / 2 }) ≡ lit 4
ex-spectrum = refl

-- Stokes drift for σ = 1/2, k = 1/40, E = 1/2: u_s = 1/80.
ex-stokes : stokes (+ 1 / 2) (+ 1 / 40) (+ 1 / 2) ≡ + 1 / 80
ex-stokes = refl
