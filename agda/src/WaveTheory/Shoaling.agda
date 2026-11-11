{-# OPTIONS --safe --without-K #-}

-- Shoaling and depth-limited breaking. New: the Lean original has neither.
--
-- Shoaling. Outside the surf zone, with no sources, no current and straight parallel depth
-- contours, the energy flux E c_g of a wave train is the same at every depth:
--
--     E₁ c_g₁ = E₂ c_g₂,   so   E₂ = E₁ c_g₁ / c_g₂   (K_s² = c_g₁ / c_g₂).
--
-- In shallow water c_g = √(g h), and the flux balance becomes Green's law, H ∝ h^(-1/4). ℚ has
-- no square root, so Green's law is stated squared: E₁² h₁ = E₂² h₂.
--
-- Breaking. The wave height in depth h is limited to γ h (Miche's criterion in its shallow
-- form, γ ≈ 0.73 in WAVEWATCH III's SDB1). With H_s² = 16 m_0 the energy cap is
-- E_max = γ² h² / 16. `breakCap` cuts one bin to it; `breakScale` scales a whole spectrum
-- down to it and keeps its shape, which is how a depth-limited limiter acts on a spectrum.
--
-- The speeds here are any rationals that meet the premises; `WaveTheory.DeepWater` and
-- `WaveTheory.Refraction` tie them to the dispersion relation of a `TanhModel`.
module WaveTheory.Shoaling where

open import Data.Nat as ℕ using (ℕ)
open import Data.Product using (_×_; _,_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _<_; _≟_; _⊓_; _<?_)
open import Data.Rational.Base using (nonNegative; positive)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; <⇒≤; *-monoˡ-≤-nonNeg; *-monoʳ-≤-nonNeg; *-zeroʳ;
         p⊓q≤p; p⊓q≤q; ⊓-glb; p≤q⇒p⊓q≡p; ⊓-monoʳ-≤; ≤-antisym)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Nullary using (Dec; yes; no)
open import Relation.Nullary.Decidable using (from-yes)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong; subst)

open import OceanWaves.Order
open import OceanWaves.Sums
open import WaveTheory.Algebra
open import WaveTheory.Moments

-- ---------------------------------------------------------------------------------------------
-- Shoaling

-- The energy at a station with group speed c_g₂, from the energy E₁ at a station with c_g₁.
shoal : ℚ → ℚ → ℚ → ℚ
shoal E₁ cg₁ cg₂ = E₁ * cg₁ /₀ cg₂

-- The shoaled energy carries the same flux.
shoal-flux : ∀ E₁ cg₁ {cg₂} → 0ℚ < cg₂ → shoal E₁ cg₁ cg₂ * cg₂ ≡ E₁ * cg₁
shoal-flux E₁ cg₁ hcg = div-mul-cancel (E₁ * cg₁) (<⇒≢0 hcg)

shoal-nonneg : ∀ {E₁ cg₁ cg₂} → 0ℚ ≤ E₁ → 0ℚ ≤ cg₁ → 0ℚ ≤ cg₂ → 0ℚ ≤ shoal E₁ cg₁ cg₂
shoal-nonneg hE h1 h2 = div-nonneg (*-nonneg hE h1) h2

-- Where the group speed drops, the energy rises: E₁ ≤ E₂ when c_g₂ ≤ c_g₁.
shoal-grows : ∀ {E₁ cg₁ cg₂} → 0ℚ ≤ E₁ → 0ℚ < cg₂ → cg₂ ≤ cg₁ → E₁ ≤ shoal E₁ cg₁ cg₂
shoal-grows {E₁} {cg₁} {cg₂} hE h2 h21 =
  le-div-of-mul-le {a = E₁ * cg₁} {b = cg₂} {c = E₁} h2 (*-monoˡ-≤-nonNeg E₁ {{nonNegative hE}} h21)

-- And where it rises, the energy drops.
shoal-decays : ∀ {E₁ cg₁ cg₂} → 0ℚ ≤ E₁ → 0ℚ < cg₂ → cg₁ ≤ cg₂ → shoal E₁ cg₁ cg₂ ≤ E₁
shoal-decays {E₁} {cg₁} {cg₂} hE h2 h12 =
  div-le-of-le-mul {a = E₁ * cg₁} {b = cg₂} {c = E₁} h2 (*-monoˡ-≤-nonNeg E₁ {{nonNegative hE}} h12)

-- Shoaling in two legs is shoaling in one: the coefficients multiply.
shoal-compose : ∀ E₁ cg₁ {cg₂} cg₃ → 0ℚ < cg₂ → shoal (shoal E₁ cg₁ cg₂) cg₂ cg₃ ≡ shoal E₁ cg₁ cg₃
shoal-compose E₁ cg₁ {cg₂} cg₃ h2 = cong (_/₀ cg₃) (shoal-flux E₁ cg₁ h2)

-- Green's law, squared. If c_g² = g h at both stations (the shallow-water limit) and the flux
-- is the same, then E₁² h₁ = E₂² h₂: the energy grows as h^(-1/2) and the height as h^(-1/4).
greens-law : ∀ {g h₁ h₂ cg₁ cg₂ E₁ E₂} → 0ℚ < g →
  cg₁ * cg₁ ≡ g * h₁ → cg₂ * cg₂ ≡ g * h₂ → E₁ * cg₁ ≡ E₂ * cg₂ →
  E₁ * E₁ * h₁ ≡ E₂ * E₂ * h₂
greens-law {g} {h₁} {h₂} {cg₁} {cg₂} {E₁} {E₂} hg c1 c2 flux = *-cancelʳ-≡ hg
  (trans (solve 3 (λ e h g → e :* e :* h :* g := e :* e :* (g :* h)) refl E₁ h₁ g)
  (trans (cong (λ u → E₁ * E₁ * u) (sym c1))
  (trans (solve 2 (λ e c → e :* e :* (c :* c) := (e :* c) :* (e :* c)) refl E₁ cg₁)
  (trans (cong (λ u → u * u) flux)
  (trans (solve 2 (λ e c → (e :* c) :* (e :* c) := e :* e :* (c :* c)) refl E₂ cg₂)
  (trans (cong (λ u → E₂ * E₂ * u) c2)
         (solve 3 (λ e h g → e :* e :* (g :* h) := e :* e :* h :* g) refl E₂ h₂ g)))))))

-- ---------------------------------------------------------------------------------------------
-- Depth-limited breaking

-- The largest energy a depth h holds: (γ h)² / 16, from H_s ≤ γ h and H_s² = 16 m_0.
emax : ℚ → ℚ → ℚ
emax γ h = γ * γ * (h * h) /₀ lit 16

private
  0<16 : 0ℚ < lit 16
  0<16 = from-yes (0ℚ <? lit 16)

emax-nonneg : ∀ γ h → 0ℚ ≤ emax γ h
emax-nonneg γ h = div-nonneg (*-nonneg (sq-nonneg γ) (sq-nonneg h)) (<⇒≤ 0<16)

-- Deeper water holds more energy.
emax-mono : ∀ γ {h h′} → 0ℚ ≤ h → h ≤ h′ → emax γ h ≤ emax γ h′
emax-mono γ {h} {h′} hh hle =
  div-monoˡ-≤ (*-monoˡ-≤-nonNeg (γ * γ) {{nonNegative (sq-nonneg γ)}} (mul-le-mul′ hle hle hh hh)) (<⇒≤ 0<16)

-- The cap reads back as the height limit: 16 E_max = (γ h)².
emax-height : ∀ γ h → lit 16 * emax γ h ≡ (γ * h) * (γ * h)
emax-height γ h =
  trans (solve 2 (λ s x → s :* x := x :* s) refl (lit 16) (emax γ h))
  (trans (div-mul-cancel (γ * γ * (h * h)) (<⇒≢0 0<16))
         (solve 2 (λ g h → g :* g :* (h :* h) := (g :* h) :* (g :* h)) refl γ h))

-- One bin cut to the cap.
breakCap : ℚ → ℚ → ℚ → ℚ
breakCap γ h E = E ⊓ emax γ h

breakCap-le : ∀ γ h E → breakCap γ h E ≤ E
breakCap-le γ h E = p⊓q≤p E (emax γ h)

breakCap-le-max : ∀ γ h E → breakCap γ h E ≤ emax γ h
breakCap-le-max γ h E = p⊓q≤q E (emax γ h)

breakCap-nonneg : ∀ γ h {E} → 0ℚ ≤ E → 0ℚ ≤ breakCap γ h E
breakCap-nonneg γ h hE = ⊓-glb hE (emax-nonneg γ h)

-- Below the cap, breaking does nothing.
breakCap-inactive : ∀ γ h {E} → E ≤ emax γ h → breakCap γ h E ≡ E
breakCap-inactive γ h hE = p≤q⇒p⊓q≡p hE

-- To cut twice is to cut once.
breakCap-idem : ∀ γ h E → breakCap γ h (breakCap γ h E) ≡ breakCap γ h E
breakCap-idem γ h E = breakCap-inactive γ h (breakCap-le-max γ h E)

-- A wave that comes into shallower water can only lose energy to breaking.
breakCap-depth : ∀ γ {h h′} E → 0ℚ ≤ h → h ≤ h′ → breakCap γ h E ≤ breakCap γ h′ E
breakCap-depth γ E hh hle = ⊓-monoʳ-≤ E (emax-mono γ hh hle)

-- The whole spectrum scaled to the cap: r = min(1, E_max / m_0), every bin times r.
breakFactor : ℚ → ℚ → ℚ → ℚ
breakFactor γ h m = 1ℚ ⊓ (emax γ h /₀ m)

breakScale : ℕ → ℚ → ℚ → (σ E : ℕ → ℚ) → ℕ → ℚ
breakScale n γ h σ E i = breakFactor γ h (m0 n σ E) * E i

private
  -- The case split on m = 0, as a function of the answer (a `with` on `m ≟ 0ℚ` does not
  -- abstract once the rationals unfold).
  scaled-le : ∀ e m → 0ℚ ≤ e → 0ℚ ≤ m → Dec (m ≡ 0ℚ) → (1ℚ ⊓ (e /₀ m)) * m ≤ e
  scaled-le e m he hm (yes refl) = subst (_≤ e) (sym (*-zeroʳ (1ℚ ⊓ (e /₀ 0ℚ)))) he
  scaled-le e m he hm (no m≢0) =
    ≤-trans (*-monoʳ-≤-nonNeg m {{nonNegative hm}} (p⊓q≤q 1ℚ (e /₀ m)))
            (≤-reflexive (div-mul-cancel e m≢0))

breakFactor-le-one : ∀ γ h m → breakFactor γ h m ≤ 1ℚ
breakFactor-le-one γ h m = p⊓q≤p 1ℚ (emax γ h /₀ m)

breakFactor-nonneg : ∀ γ h {m} → 0ℚ ≤ m → 0ℚ ≤ breakFactor γ h m
breakFactor-nonneg γ h hm = ⊓-glb (<⇒≤ 0<1) (div-nonneg (emax-nonneg γ h) hm)

-- After scaling, the spectrum is non-negative, no bin grows, and H_s ≤ γ h.
breakScale-nonneg : ∀ n γ h σ E → NonNeg n E → NonNeg n (breakScale n γ h σ E)
breakScale-nonneg n γ h σ E hE i hi =
  *-nonneg (breakFactor-nonneg γ h (sumTo-nonneg n E hE)) (hE i hi)

breakScale-le : ∀ n γ h σ E → NonNeg n E → ∀ i → i ℕ.< n → breakScale n γ h σ E i ≤ E i
breakScale-le n γ h σ E hE i hi =
  ≤-trans (*-monoʳ-≤-nonNeg (E i) {{nonNegative (hE i hi)}} (breakFactor-le-one γ h (m0 n σ E)))
          (≤-reflexive (solve 1 (λ e → con 1ℚ :* e := e) refl (E i)))

breakScale-m0 : ∀ n γ h σ E → m0 n σ (breakScale n γ h σ E) ≡ breakFactor γ h (m0 n σ E) * m0 n σ E
breakScale-m0 n γ h σ E = sumTo-mul-left n (breakFactor γ h (m0 n σ E)) E

breakScale-hs : ∀ n γ h σ E → NonNeg n E → hs2 n σ (breakScale n γ h σ E) ≤ (γ * h) * (γ * h)
breakScale-hs n γ h σ E hE =
  ≤-trans (≤-reflexive (cong (lit 16 *_) (breakScale-m0 n γ h σ E)))
  (≤-trans (*-monoˡ-≤-nonNeg (lit 16) {{nonNegative (<⇒≤ 0<16)}}
              (scaled-le (emax γ h) m (emax-nonneg γ h) hm (m ≟ 0ℚ)))
           (≤-reflexive (emax-height γ h)))
  where
  m  = m0 n σ E
  hm = sumTo-nonneg n E hE

-- A sea that already fits the depth is not touched.
breakScale-inactive : ∀ n γ h σ E → 0ℚ < m0 n σ E → m0 n σ E ≤ emax γ h →
  ∀ i → breakScale n γ h σ E i ≡ E i
breakScale-inactive n γ h σ E hm hle i =
  trans (cong (_* E i) (p≤q⇒p⊓q≡p (le-div-of-mul-le {a = emax γ h} {b = m0 n σ E} {c = 1ℚ} hm
                         (≤-trans (≤-reflexive (solve 1 (λ m → con 1ℚ :* m := m) refl (m0 n σ E))) hle))))
        (solve 1 (λ e → con 1ℚ :* e := e) refl (E i))
