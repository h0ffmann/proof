{-# OPTIONS --safe --without-K #-}

-- Source terms and their time integration. Ported from
-- `ocean-waves/lean/OceanWaves/Sources.lean`. The names follow Lean, with `-` for `_`.
--
-- The right-hand side of the action balance equation is S / σ with S = S_in + S_nl + S_ds
-- (wind input, nonlinear transfer, whitecapping). One representative of each, in the forms of
-- the WAM model family. The constants are parameters; no proof uses their values.
--
-- * S_in = β N, β = max(0, c_in (ρ_a/ρ_w) (28 u*/c · cos(θ - θ_w) - 1)) σ (Snyder et al. 1981,
--   as adapted by Komen et al. 1984).
-- * S_ds = -γ N, γ = C_ds σ̄ (α̂/α̂_PM)² ((1 - δ) k/k̄ + δ (k/k̄)²), the WAM Cycle 4 form.
-- * S_nl: a sum of quadruplet exchanges, the structure of the Discrete Interaction
--   Approximation. Each exchange takes 2d from one bin and gives d to each neighbour.
--
-- This module proves: β ≥ 0 and γ ≥ 0, and no input when the wave outruns the wind; S_nl keeps
-- the total action for any exchange amounts, and the total energy Σ σ N on a uniform frequency
-- grid; the semi-implicit step N* = N (1 + Δt β) / (1 + Δt γ) keeps N ≥ 0 for every Δt ≥ 0,
-- where explicit Euler needs Δt (γ - β) ≤ 1; the limiter keeps N ≥ 0, and when it does not
-- clip, the source step keeps the action of the nonlinear transfer.
--
-- Differences from Lean: Lean's `if j + 1 = c then 1 else 0` is `if suc j ≡ᵇ c then 1ℚ else
-- 0ℚ`, and `if Interior n c then x else 0` is `gate (interior? n c) x`, a function of the
-- answer that the proofs match on. `max` and `min` are `_⊔_` and `_⊓_` of the standard library,
-- which Lean's `max` and `min` equal case by case.
module OceanWaves.Sources where

open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.Nat as ℕ using (ℕ; zero; suc; _∸_; _≡ᵇ_)
import Data.Nat.Properties as ℕP
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Nullary.Decidable using () renaming (_×-dec_ to _×?_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; _≤_; _<_; _⊔_; _⊓_)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; <⇒≤; ≤-reflexive; *-monoˡ-≤-nonNeg; +-monoʳ-≤; +-inverseʳ;
         *-identityˡ; p≤p⊔q; p⊓q≤p; ⊔-lub; p≥q⇒p⊔q≡p; p≤q⇒p⊔q≡q; p≥q⇒p⊓q≡q)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; :-_; con)
open import Relation.Nullary using (Dec; yes; no)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst; subst₂)

open import OceanWaves.Order
open import OceanWaves.Sums

-- ---------------------------------------------------------------------------------------------
-- Wind input

record WindParams : Set where
  field
    cIn        : ℚ   -- coefficient c_in (0.25 in Snyder et al.)
    rhoRatio   : ℚ   -- density ratio ρ_a / ρ_w
    ustar      : ℚ   -- friction velocity u*
    cIn-nonneg : 0ℚ ≤ cIn
    rho-nonneg : 0ℚ ≤ rhoRatio
open WindParams

-- The growth rate β of a component with frequency σ, phase speed c and cosRel = cos(θ - θ_w).
windRate : WindParams → ℚ → ℚ → ℚ → ℚ
windRate P σ c cosRel = (0ℚ ⊔ (cIn P * rhoRatio P * (lit 28 * ustar P * cosRel /₀ c - 1ℚ))) * σ

windRate-nonneg : ∀ P {σ} c cosRel → 0ℚ ≤ σ → 0ℚ ≤ windRate P σ c cosRel
windRate-nonneg P c cosRel hσ =
  *-nonneg (p≤p⊔q 0ℚ (cIn P * rhoRatio P * (lit 28 * ustar P * cosRel /₀ c - 1ℚ))) hσ

-- No input when the wave outruns the wind: 28 u* cos / c ≤ 1 gives β = 0.
windRate-zero : ∀ P σ c cosRel → lit 28 * ustar P * cosRel /₀ c ≤ 1ℚ → windRate P σ c cosRel ≡ 0ℚ
windRate-zero P σ c cosRel h =
  trans (cong (_* σ) (p≥q⇒p⊔q≡p inner≤0)) (solve 1 (λ s → con 0ℚ :* s := con 0ℚ) refl σ)
  where
  y = lit 28 * ustar P * cosRel /₀ c
  cr = cIn P * rhoRatio P
  inner≤0 : cr * (y - 1ℚ) ≤ 0ℚ
  inner≤0 = ≤-trans (*-monoˡ-≤-nonNeg cr {{nonNegative (*-nonneg (cIn-nonneg P) (rho-nonneg P))}}
                       (by-diff {a = y - 1ℚ} {b = 0ℚ} (1ℚ - y)
                          (solve 2 (λ y o → con 0ℚ :- (y :- o) := o :- y) refl y 1ℚ) (≤⇒0≤- h)))
                    (≤-reflexive (solve 1 (λ x → x :* con 0ℚ := con 0ℚ) refl cr))

-- ---------------------------------------------------------------------------------------------
-- Whitecapping (WAM Cycle 4 form)

record DsParams : Set where
  field
    cDs          : ℚ
    delta        : ℚ
    alphaPM      : ℚ
    cDs-nonneg   : 0ℚ ≤ cDs
    delta-nonneg : 0ℚ ≤ delta
    delta-le-one : delta ≤ 1ℚ
open DsParams

-- The discrete spectrum on n bins: frequency, wavenumber, quadrature weight (bin width times
-- direction width) and action density.
record Spectrum : Set where
  field
    n : ℕ
    σ : ℕ → ℚ
    k : ℕ → ℚ
    w : ℕ → ℚ
    N : ℕ → ℚ

module _ (S : Spectrum) where
  open Spectrum S

  energy : ℕ → ℚ
  energy i = σ i * N i

  Etot : ℚ
  Etot = sumTo n (λ i → w i * energy i)

  -- The mean frequency σ̄ = E / Σ w E/σ (WAM's ⟨σ⁻¹⟩⁻¹).
  σMean : ℚ
  σMean = Etot /₀ sumTo n (λ i → w i * energy i /₀ σ i)

  -- The mean wavenumber k̄ = E / Σ w E/k. WAM uses the k^(-1/2) moment; the k⁻¹ moment needs no
  -- square root.
  kMean : ℚ
  kMean = Etot /₀ sumTo n (λ i → w i * energy i /₀ k i)

  -- The integral steepness α̂ = E k̄².
  steep : ℚ
  steep = Etot * (kMean * kMean)

  -- A physically admissible spectrum: positive frequencies and wavenumbers, non-negative
  -- weights and action.
  Admissible : Set
  Admissible = ∀ i → i ℕ.< n → 0ℚ < σ i × 0ℚ < k i × 0ℚ ≤ w i × 0ℚ ≤ N i

  private
    wE-nonneg : Admissible → ∀ i → i ℕ.< n → 0ℚ ≤ w i * energy i
    wE-nonneg hS i hi = let (s , _ , hw , hN) = hS i hi in *-nonneg hw (*-nonneg (<⇒≤ s) hN)

  Etot-nonneg : Admissible → 0ℚ ≤ Etot
  Etot-nonneg hS = sumTo-nonneg n _ (wE-nonneg hS)

  σMean-nonneg : Admissible → 0ℚ ≤ σMean
  σMean-nonneg hS = div-nonneg (Etot-nonneg hS) (sumTo-nonneg n _ λ i hi →
    div-nonneg (wE-nonneg hS i hi) (<⇒≤ (proj₁ (hS i hi))))

  kMean-nonneg : Admissible → 0ℚ ≤ kMean
  kMean-nonneg hS = div-nonneg (Etot-nonneg hS) (sumTo-nonneg n _ λ i hi →
    div-nonneg (wE-nonneg hS i hi) (<⇒≤ (proj₁ (proj₂ (hS i hi)))))

-- The whitecapping rate γ of bin i.
dsRate : DsParams → Spectrum → ℕ → ℚ
dsRate P S i = cDs P * σMean S * (r * r) * ((1ℚ - delta P) * q + delta P * (q * q))
  where
  r = steep S /₀ alphaPM P
  q = Spectrum.k S i /₀ kMean S

-- Whitecapping only dissipates: γ ≥ 0 on every admissible spectrum.
dsRate-nonneg : ∀ P S → Admissible S → ∀ i → i ℕ.< Spectrum.n S → 0ℚ ≤ dsRate P S i
dsRate-nonneg P S hS i hi =
  *-nonneg (*-nonneg (*-nonneg (cDs-nonneg P) (σMean-nonneg S hS)) (sq-nonneg (steep S /₀ alphaPM P)))
           (+-nonneg (*-nonneg (≤⇒0≤- (delta-le-one P)) hq) (*-nonneg (delta-nonneg P) (*-nonneg hq hq)))
  where
  hq : 0ℚ ≤ Spectrum.k S i /₀ kMean S
  hq = div-nonneg (<⇒≤ (proj₁ (proj₂ (hS i hi)))) (kMean-nonneg S hS)

-- ---------------------------------------------------------------------------------------------
-- Nonlinear transfer: quadruplet exchanges

-- The quadruplet resonance of the DIA: two waves at σ interact with waves at σ(1+λ) and
-- σ(1-λ). The frequency condition σ₁ + σ₂ = σ₃ + σ₄ holds for every λ.
dia-resonance : ∀ σ lam → σ + σ ≡ σ * (1ℚ + lam) + σ * (1ℚ - lam)
dia-resonance = solve 2 (λ s l → s :+ s := s :* (con 1ℚ :+ l) :+ s :* (con 1ℚ :- l)) refl

-- The elementary exchange centred on bin c, seen from bin j: +1 at c ± 1, -2 at c.
quad : ℕ → ℕ → ℚ
quad c j = (if suc j ≡ᵇ c then 1ℚ else 0ℚ) + (if j ≡ᵇ suc c then 1ℚ else 0ℚ) - (if j ≡ᵇ c then 2ℚ else 0ℚ)

-- A centre is interior if both neighbours exist.
Interior : ℕ → ℕ → Set
Interior n c = 1 ℕ.≤ c × suc c ℕ.< n

interior? : ∀ n c → Dec (Interior n c)
interior? n c = (1 ℕ.≤? c) ×? (suc c ℕ.<? n)

-- x when the answer is yes, else 0: Lean's `if p then x else 0`.
gate : ∀ {P : Set} → Dec P → ℚ → ℚ
gate (yes _) x = x
gate (no  _) x = 0ℚ

-- The nonlinear source in bin j, from the exchange amounts d c at every interior centre.
snl : ℕ → (ℕ → ℚ) → ℕ → ℚ
snl n d j = sumTo n (λ c → gate (interior? n c) (d c * quad c j))

private
  ind : Bool → ℚ → ℚ
  ind b x = if b then x else 0ℚ

  quad-split : ∀ b₁ b₂ b₃ x →
    x * (ind b₁ 1ℚ + ind b₂ 1ℚ - ind b₃ 2ℚ) ≡ ind b₁ x + ind b₂ x - ind b₃ (2ℚ * x)
  quad-split true  true  true  = solve 1 (λ x → x :* (con 1ℚ :+ con 1ℚ :- con 2ℚ) := x :+ x :- con 2ℚ :* x) refl
  quad-split true  true  false = solve 1 (λ x → x :* (con 1ℚ :+ con 1ℚ :- con 0ℚ) := x :+ x :- con 0ℚ) refl
  quad-split true  false true  = solve 1 (λ x → x :* (con 1ℚ :+ con 0ℚ :- con 2ℚ) := x :+ con 0ℚ :- con 2ℚ :* x) refl
  quad-split true  false false = solve 1 (λ x → x :* (con 1ℚ :+ con 0ℚ :- con 0ℚ) := x :+ con 0ℚ :- con 0ℚ) refl
  quad-split false true  true  = solve 1 (λ x → x :* (con 0ℚ :+ con 1ℚ :- con 2ℚ) := con 0ℚ :+ x :- con 2ℚ :* x) refl
  quad-split false true  false = solve 1 (λ x → x :* (con 0ℚ :+ con 1ℚ :- con 0ℚ) := con 0ℚ :+ x :- con 0ℚ) refl
  quad-split false false true  = solve 1 (λ x → x :* (con 0ℚ :+ con 0ℚ :- con 2ℚ) := con 0ℚ :+ con 0ℚ :- con 2ℚ :* x) refl
  quad-split false false false = solve 1 (λ x → x :* (con 0ℚ :+ con 0ℚ :- con 0ℚ) := con 0ℚ :+ con 0ℚ :- con 0ℚ) refl

  gate-mul : ∀ {P : Set} (D : Dec P) a x → a * gate D x ≡ gate D (a * x)
  gate-mul (yes _) a x = refl
  gate-mul (no  _) a x = solve 1 (λ a → a :* con 0ℚ := con 0ℚ) refl a

  gate-cong : ∀ {P : Set} (D : Dec P) {x y} → x ≡ y → gate D x ≡ gate D y
  gate-cong D refl = refl

-- Σ_j w_j · quad c j = w(c-1) + w(c+1) - 2 w(c), for an interior centre.
quad-moment : ∀ n c (w : ℕ → ℚ) → Interior n c →
  sumTo n (λ j → w j * quad c j) ≡ w (c ∸ 1) + w (suc c) - 2ℚ * w c
quad-moment n (suc c) w (_ , c+1<n) =
  trans (sumTo-congr n _ (λ j → pick c w j + pick (suc (suc c)) w j - pick (suc c) (λ i → 2ℚ * w i) j)
           (λ j _ → quad-split (j ≡ᵇ c) (j ≡ᵇ suc (suc c)) (j ≡ᵇ suc c) (w j)))
    (trans (sumTo-sub n (λ j → pick c w j + pick (suc (suc c)) w j) (pick (suc c) (λ i → 2ℚ * w i)))
      (trans (cong (_- sumTo n (pick (suc c) (λ i → 2ℚ * w i))) (sumTo-add n (pick c w) (pick (suc (suc c)) w)))
        (cong₂ _-_ (cong₂ _+_ (sumTo-pick n c w (ℕP.<-trans (ℕP.n<1+n c) (ℕP.<-trans (ℕP.n<1+n (suc c)) c+1<n)))
                              (sumTo-pick n (suc (suc c)) w c+1<n))
                   (sumTo-pick n (suc c) (λ i → 2ℚ * w i) (ℕP.<-trans (ℕP.n<1+n (suc c)) c+1<n)))))

-- The weighted total of the nonlinear source.
snl-moment : ∀ n (d w : ℕ → ℚ) →
  sumTo n (λ j → w j * snl n d j)
    ≡ sumTo n (λ c → gate (interior? n c) (d c * (w (c ∸ 1) + w (suc c) - 2ℚ * w c)))
snl-moment n d w =
  trans (sumTo-congr n _ (λ j → sumTo n (λ c → gate (interior? n c) (d c * (w j * quad c j)))) inside)
    (trans (sumTo-comm n n (λ j c → gate (interior? n c) (d c * (w j * quad c j))))
      (sumTo-congr n _ _ (λ c _ → per-centre c (interior? n c))))
  where
  inside : ∀ j → j ℕ.< n → w j * snl n d j ≡ sumTo n (λ c → gate (interior? n c) (d c * (w j * quad c j)))
  inside j _ =
    trans (sym (sumTo-mul-left n (w j) (λ c → gate (interior? n c) (d c * quad c j))))
      (sumTo-congr n _ _ λ c _ →
        trans (gate-mul (interior? n c) (w j) (d c * quad c j))
              (gate-cong (interior? n c) (solve 3 (λ a b q → a :* (b :* q) := b :* (a :* q)) refl (w j) (d c) (quad c j))))
  per-centre : ∀ c (D : Dec (Interior n c)) →
    sumTo n (λ j → gate D (d c * (w j * quad c j))) ≡ gate D (d c * (w (c ∸ 1) + w (suc c) - 2ℚ * w c))
  per-centre c (yes hc) = trans (sumTo-mul-left n (d c) (λ j → w j * quad c j)) (cong (d c *_) (quad-moment n c w hc))
  per-centre c (no  _)  = sumTo-zero-fn n

private
  gate-zero : ∀ {P : Set} (D : Dec P) {x} → x ≡ 0ℚ → gate D x ≡ 0ℚ
  gate-zero (yes _) eq = eq
  gate-zero (no  _) eq = refl

-- The nonlinear transfer keeps the total action, for any exchange amounts.
snl-conserves-action : ∀ n (d : ℕ → ℚ) → sumTo n (snl n d) ≡ 0ℚ
snl-conserves-action n d =
  trans (sumTo-congr n _ _ (λ j _ → sym (*-identityˡ (snl n d j))))
    (trans (snl-moment n d (λ _ → 1ℚ))
      (trans (sumTo-congr n _ (λ _ → 0ℚ) (λ c _ →
                gate-zero (interior? n c) (solve 1 (λ x → x :* (con 1ℚ :+ con 1ℚ :- (con 1ℚ :+ con 1ℚ) :* con 1ℚ) := con 0ℚ) refl (d c))))
             (sumTo-zero-fn n)))

-- The nonlinear transfer keeps the total energy Σ σ_j S_nl,j on a uniform frequency grid.
snl-conserves-energy : ∀ n (d σ : ℕ → ℚ) → (∀ c → Interior n c → σ (c ∸ 1) + σ (suc c) ≡ 2ℚ * σ c) →
  sumTo n (λ j → σ j * snl n d j) ≡ 0ℚ
snl-conserves-energy n d σ hlin =
  trans (snl-moment n d σ)
    (trans (sumTo-congr n _ (λ _ → 0ℚ) (λ c _ → per c (interior? n c))) (sumTo-zero-fn n))
  where
  per : ∀ c (D : Dec (Interior n c)) → gate D (d c * (σ (c ∸ 1) + σ (suc c) - 2ℚ * σ c)) ≡ 0ℚ
  per c (yes hc) = trans (cong (λ u → d c * (u - 2ℚ * σ c)) (hlin c hc))
                         (solve 2 (λ a s → a :* (con 2ℚ :* s :- con 2ℚ :* s) := con 0ℚ) refl (d c) (σ c))
  per c (no  _)  = refl

-- ---------------------------------------------------------------------------------------------
-- Time integration of the sources

-- The WAM-style semi-implicit step of the linear part: input explicit, dissipation implicit,
-- N* = N (1 + Δt β) / (1 + Δt γ).
linStep : ℚ → ℚ → ℚ → ℚ → ℚ
linStep Δt β γ N = N * (1ℚ + Δt * β) /₀ (1ℚ + Δt * γ)

-- The semi-implicit step keeps N ≥ 0 for every Δt ≥ 0.
linStep-nonneg : ∀ {Δt β γ N} → 0ℚ ≤ Δt → 0ℚ ≤ β → 0ℚ ≤ γ → 0ℚ ≤ N → 0ℚ ≤ linStep Δt β γ N
linStep-nonneg ht hβ hγ hN =
  div-nonneg (*-nonneg hN (+-nonneg (<⇒≤ 0<1) (*-nonneg ht hβ))) (+-nonneg (<⇒≤ 0<1) (*-nonneg ht hγ))

-- With no wind, the semi-implicit step only damps: N* ≤ N.
linStep-damps : ∀ {Δt γ N} → 0ℚ ≤ Δt → 0ℚ ≤ γ → 0ℚ ≤ N → linStep Δt 0ℚ γ N ≤ N
linStep-damps {Δt} {γ} {N} ht hγ hN =
  div-le-of-le-mul (+-pos 0<1 (*-nonneg ht hγ))
    (by-diff {a = N * (1ℚ + Δt * 0ℚ)} {b = N * (1ℚ + Δt * γ)} (N * (Δt * γ))
       (solve 3 (λ n t g → n :* (con 1ℚ :+ t :* g) :- n :* (con 1ℚ :+ t :* con 0ℚ) := n :* (t :* g)) refl N Δt γ)
       (*-nonneg hN (*-nonneg ht hγ)))

-- Explicit Euler, for comparison.
eulerStep : ℚ → ℚ → ℚ → ℚ → ℚ
eulerStep Δt β γ N = N + Δt * (β - γ) * N

-- Explicit Euler keeps N ≥ 0 only under a time-step restriction.
eulerStep-nonneg : ∀ {Δt β γ N} → 0ℚ ≤ N → Δt * (γ - β) ≤ 1ℚ → 0ℚ ≤ eulerStep Δt β γ N
eulerStep-nonneg {Δt} {β} {γ} {N} hN h =
  subst (0ℚ ≤_) (solve 4 (λ t b g n → (con 1ℚ :- t :* (g :- b)) :* n := n :+ t :* (b :- g) :* n) refl Δt β γ N)
    (*-nonneg (≤⇒0≤- h) hN)

-- The limiter: clip the increment x to [-N*, L]. WAM limits |ΔN| by a value L from the wind
-- (Hersbach and Janssen 1999); the lower clip -N* keeps N ≥ 0.
limit : ℚ → ℚ → ℚ → ℚ
limit Nstar L x = (- Nstar) ⊔ (L ⊓ x)

-- One source step for bin i: the semi-implicit linear part, then the limited nonlinear
-- increment.
sourceStep : ℚ → ℚ → (β γ : ℕ → ℚ) → ℕ → (d N : ℕ → ℚ) → ℕ → ℚ
sourceStep Δt L β γ n d N i =
  linStep Δt (β i) (γ i) (N i) + limit (linStep Δt (β i) (γ i) (N i)) L (Δt * snl n d i)

-- The full source step keeps N ≥ 0, for every Δt. The lower clip -N* gives it by
-- construction; `linStep-nonneg` shows that N* ≥ 0, so the clip only trims a removal that is
-- too large and never lifts a negative value.
sourceStep-nonneg : ∀ Δt L β γ n d N i → 0ℚ ≤ sourceStep Δt L β γ n d N i
sourceStep-nonneg Δt L β γ n d N i =
  ≤-trans (≤-reflexive (sym (+-inverseʳ s))) (+-monoʳ-≤ s (p≤p⊔q (- s) (L ⊓ (Δt * snl n d i))))
  where s = linStep Δt (β i) (γ i) (N i)

-- The limiter bounds the nonlinear increment by L from above.
limit-le : ∀ Nstar L x → - Nstar ≤ L → limit Nstar L x ≤ L
limit-le Nstar L x hL = ⊔-lub hL (p⊓q≤p L x)

-- When the limiter does not clip, it is the identity.
limit-inactive : ∀ {Nstar L x} → - Nstar ≤ x → x ≤ L → limit Nstar L x ≡ x
limit-inactive {Nstar} {L} {x} h1 h2 = trans (cong (- Nstar ⊔_) (p≥q⇒p⊓q≡q h2)) (p≤q⇒p⊔q≡q h1)

-- The action budget of the source step. If the limiter does not clip in any bin, the total
-- action changes only through the linear terms: the nonlinear transfer moves action between
-- bins and makes none.
sourceStep-sum : ∀ {Δt L} {β γ d N : ℕ → ℚ} {n} →
  (∀ i → i ℕ.< n → - linStep Δt (β i) (γ i) (N i) ≤ Δt * snl n d i × Δt * snl n d i ≤ L) →
  sumTo n (sourceStep Δt L β γ n d N) ≡ sumTo n (λ i → linStep Δt (β i) (γ i) (N i))
sourceStep-sum {Δt} {L} {β} {γ} {d} {N} {n} hfree =
  trans (sumTo-congr n _ (λ i → linStep Δt (β i) (γ i) (N i) + Δt * snl n d i)
           (λ i hi → cong (linStep Δt (β i) (γ i) (N i) +_) (limit-inactive (proj₁ (hfree i hi)) (proj₂ (hfree i hi)))))
    (trans (sumTo-add n (λ i → linStep Δt (β i) (γ i) (N i)) (λ i → Δt * snl n d i))
      (trans (cong (sumTo n (λ i → linStep Δt (β i) (γ i) (N i)) +_)
                   (trans (sumTo-mul-left n Δt (snl n d)) (cong (Δt *_) (snl-conserves-action n d))))
             (solve 2 (λ s t → s :+ t :* con 0ℚ := s) refl _ Δt)))
