{-# OPTIONS --safe --without-K #-}

-- The radiation stress of a linear wave train (Longuet-Higgins and Stewart, 1964,
-- doi:10.1016/0011-7471(64)90001-4). New: the Lean original has no momentum flux.
--
-- For a wave train of energy E, ratio n = c_g / c, and direction (c, s) = (cos θ, sin θ)
-- with c² + s² = 1:
--
--     S_xx = E (n (1 + c²) - 1/2),   S_xy = E n c s,   S_yy = E (n (1 + s²) - 1/2).
--
-- WAVEWATCH III writes these as an output field (SXX, SXY, SYY). ℚ has no cosine, so the
-- direction is any rational pair on the unit circle, as in `WaveTheory.Refraction`.
--
-- What this module proves:
--
-- * the trace and the determinant of the tensor do not depend on the direction:
--   S_xx + S_yy = E (3n - 1) and S_xx S_yy - S_xy² = E² (2n - 1/2)(n - 1/2);
-- * for 1/2 ≤ n ≤ 1 (every `TanhModel`, `OceanWaves.Dispersion`), S_xx ≥ 0 and the
--   determinant is ≥ 0, so the tensor is positive semi-definite in every depth;
-- * in deep water (n = 1/2) the determinant is zero: the stress acts only along the ray,
--   S = (E/2) (c, s) ⊗ (c, s);
-- * the classical values at normal incidence: S_xx = E (2n - 1/2), which is E/2 in deep
--   water and 3E/2 in shallow water;
-- * Longuet-Higgins' form of the alongshore stress: S_xy = (E c_g cos θ) (sin θ / C), the
--   shore-normal energy flux times the Snell invariant. Outside the surf zone both factors
--   are kept (`WaveTheory.Shoaling`, `WaveTheory.Refraction`), so S_xy is kept too
--   (`sxy-kept`). Where waves break, the flux drops and S_xy changes: that change drives the
--   longshore current.
module WaveTheory.RadiationStress where

open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; _≤_; _<_)
open import Data.Rational.Properties using (≤-refl; ≤-trans; ≤-reflexive; <⇒≤; *-identityʳ)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂)

open import OceanWaves.Order
open import OceanWaves.Dispersion

-- One half, in the form `OceanWaves.Dispersion.nFactor-ge-half` uses.
½ : ℚ
½ = 1ℚ /₀ 2ℚ

two-halves : ½ + ½ ≡ 1ℚ
two-halves = trans (solve 1 (λ i → con 1ℚ :* i :+ con 1ℚ :* i := (con 1ℚ :+ con 1ℚ) :* i) refl (inv₀ 2ℚ))
                   (inv₀-inverse 2ℚ (<⇒≢0 0<2))

0≤½ : 0ℚ ≤ ½
0≤½ = div-nonneg (<⇒≤ 0<1) (<⇒≤ 0<2)

-- A direction on the unit circle: (cos θ, sin θ) with no angle behind it.
record Direction : Set where
  constructor dir
  field
    cs sn : ℚ
    unit  : cs * cs + sn * sn ≡ 1ℚ
open Direction public

-- The wave that comes in along the x axis (θ = 0).
normal : Direction
normal = dir 1ℚ 0ℚ refl

module _ (E n : ℚ) (d : Direction) where
  private
    c = cs d
    s = sn d

  Sxx Sxy Syy : ℚ
  Sxx = E * (n * (1ℚ + c * c) - ½)
  Sxy = E * n * c * s
  Syy = E * (n * (1ℚ + s * s) - ½)

  -- The trace: S_xx + S_yy = E (3n - 1), in every direction.
  stress-trace : Sxx + Syy ≡ E * ((1ℚ + 1ℚ + 1ℚ) * n - 1ℚ)
  stress-trace =
    trans (solve 5 (λ E n c s h →
             E :* (n :* (con 1ℚ :+ c :* c) :- h) :+ E :* (n :* (con 1ℚ :+ s :* s) :- h)
             := E :* (n :* (con 1ℚ :+ con 1ℚ :+ (c :* c :+ s :* s)) :- (h :+ h))) refl E n c s ½)
    (trans (cong₂ (λ u t → E * (n * (1ℚ + 1ℚ + u) - t)) (unit d) two-halves)
           (solve 2 (λ E n → E :* (n :* (con 1ℚ :+ con 1ℚ :+ con 1ℚ) :- con 1ℚ)
                             := E :* ((con 1ℚ :+ con 1ℚ :+ con 1ℚ) :* n :- con 1ℚ)) refl E n))

  -- The determinant: S_xx S_yy - S_xy² = E² (2n - 1/2)(n - 1/2), in every direction.
  stress-det : Sxx * Syy - Sxy * Sxy ≡ E * E * ((n + n - ½) * (n - ½))
  stress-det =
    trans (solve 5 (λ E n c s h →
             E :* (n :* (con 1ℚ :+ c :* c) :- h) :* (E :* (n :* (con 1ℚ :+ s :* s) :- h))
               :- E :* n :* c :* s :* (E :* n :* c :* s)
             := E :* E :* (n :* n :* (con 1ℚ :+ (c :* c :+ s :* s))
                           :- h :* n :* (con 1ℚ :+ con 1ℚ :+ (c :* c :+ s :* s)) :+ h :* h)) refl E n c s ½)
    (trans (cong (λ u → E * E * (n * n * (1ℚ + u) - ½ * n * (1ℚ + 1ℚ + u) + ½ * ½)) (unit d))
           (solve 3 (λ E n h →
              E :* E :* (n :* n :* (con 1ℚ :+ con 1ℚ) :- h :* n :* (con 1ℚ :+ con 1ℚ :+ con 1ℚ) :+ h :* h)
              := E :* E :* ((n :+ n :- h) :* (n :- h))) refl E n ½))

  -- For n ≥ 1/2 and E ≥ 0, the normal stresses are non-negative ...
  Sxx-nonneg : 0ℚ ≤ E → ½ ≤ n → 0ℚ ≤ Sxx
  Sxx-nonneg hE hn = *-nonneg hE
    (by-diff {a = 0ℚ} {b = n * (1ℚ + c * c) - ½} ((n - ½) + n * (c * c))
       (solve 4 (λ n c h z → n :* (con 1ℚ :+ c :* c) :- h :- con 0ℚ := (n :- h) :+ n :* (c :* c)) refl n c ½ 0ℚ)
       (+-nonneg (≤⇒0≤- hn) (*-nonneg (≤-trans 0≤½ hn) (sq-nonneg c))))

  Syy-nonneg : 0ℚ ≤ E → ½ ≤ n → 0ℚ ≤ Syy
  Syy-nonneg hE hn = *-nonneg hE
    (by-diff {a = 0ℚ} {b = n * (1ℚ + s * s) - ½} ((n - ½) + n * (s * s))
       (solve 4 (λ n s h z → n :* (con 1ℚ :+ s :* s) :- h :- con 0ℚ := (n :- h) :+ n :* (s :* s)) refl n s ½ 0ℚ)
       (+-nonneg (≤⇒0≤- hn) (*-nonneg (≤-trans 0≤½ hn) (sq-nonneg s))))

  -- ... and the determinant is non-negative: the tensor is positive semi-definite.
  stress-det-nonneg : ½ ≤ n → 0ℚ ≤ Sxx * Syy - Sxy * Sxy
  stress-det-nonneg hn =
    subst′ (*-nonneg (sq-nonneg E) (*-nonneg two-n-half (≤⇒0≤- hn)))
    where
    subst′ : 0ℚ ≤ E * E * ((n + n - ½) * (n - ½)) → 0ℚ ≤ Sxx * Syy - Sxy * Sxy
    subst′ h = ≤-trans h (≤-reflexive (sym stress-det))
    two-n-half : 0ℚ ≤ n + n - ½
    two-n-half = by-diff {a = 0ℚ} {b = n + n - ½} ((n - ½) + n)
                   (solve 3 (λ n h z → n :+ n :- h :- con 0ℚ := (n :- h) :+ n) refl n ½ 0ℚ)
                   (+-nonneg (≤⇒0≤- hn) (≤-trans 0≤½ hn))

  -- In deep water the determinant is zero, and S_xx = E c² / 2: the stress acts along the ray.
  stress-det-deep : n ≡ ½ → Sxx * Syy - Sxy * Sxy ≡ 0ℚ
  stress-det-deep refl =
    trans stress-det (solve 2 (λ E h → E :* E :* ((h :+ h :- h) :* (h :- h)) := con 0ℚ) refl E ½)

  Sxx-deep : n ≡ ½ → Sxx ≡ E * ½ * (c * c)
  Sxx-deep refl = solve 3 (λ E h c → E :* (h :* (con 1ℚ :+ c :* c) :- h) := E :* h :* (c :* c)) refl E ½ c

  -- Longuet-Higgins' form: with c_g = n C and C ≠ 0, S_xy is the shore-normal energy flux
  -- E c_g cos θ times the Snell invariant sin θ / C.
  Sxy-flux-form : ∀ C → C ≢ 0ℚ → Sxy ≡ (E * (n * C) * c) * (s /₀ C)
  Sxy-flux-form C C≢0 = sym
    (trans (solve 6 (λ E n C c s v → E :* (n :* C) :* c :* (s :* v) := E :* n :* c :* s :* (C :* v))
              refl E n C c s (inv₀ C))
           (trans (cong (E * n * c * s *_) (inv₀-inverse C C≢0)) (*-identityʳ _)))

-- At normal incidence: S_xx = E (2n - 1/2) and S_xy = 0.
Sxx-normal : ∀ E n → Sxx E n normal ≡ E * (n + n - ½)
Sxx-normal E n = solve 3 (λ E n h → E :* (n :* (con 1ℚ :+ con 1ℚ :* con 1ℚ) :- h) := E :* (n :+ n :- h)) refl E n ½

Sxy-normal : ∀ E n → Sxy E n normal ≡ 0ℚ
Sxy-normal E n = solve 2 (λ E n → E :* n :* con 1ℚ :* con 0ℚ := con 0ℚ) refl E n

-- Deep water (n = 1/2) gives S_xx = E/2; shallow water (n = 1) gives S_xx = 3E/2.
Sxx-normal-deep : ∀ E → Sxx E ½ normal ≡ E * ½
Sxx-normal-deep E = trans (Sxx-normal E ½) (solve 2 (λ E h → E :* (h :+ h :- h) := E :* h) refl E ½)

Sxx-normal-shallow : ∀ E → Sxx E 1ℚ normal ≡ E * (1ℚ + ½)
Sxx-normal-shallow E =
  trans (Sxx-normal E 1ℚ)
        (trans (cong (λ t → E * (t + t - ½)) (sym two-halves))
               (solve 2 (λ E h → E :* ((h :+ h) :+ (h :+ h) :- h) := E :* ((h :+ h) :+ h)) refl E ½
                ⟨trans⟩ cong (λ t → E * (t + ½)) two-halves))
  where _⟨trans⟩_ = trans

-- Outside the surf zone the shore-normal energy flux and the Snell invariant are both kept, so
-- S_xy is kept: two stations with the same flux and the same invariant have the same S_xy.
sxy-kept : ∀ E₁ n₁ d₁ C₁ E₂ n₂ d₂ C₂ → C₁ ≢ 0ℚ → C₂ ≢ 0ℚ →
  E₁ * (n₁ * C₁) * cs d₁ ≡ E₂ * (n₂ * C₂) * cs d₂ →
  sn d₁ /₀ C₁ ≡ sn d₂ /₀ C₂ →
  Sxy E₁ n₁ d₁ ≡ Sxy E₂ n₂ d₂
sxy-kept E₁ n₁ d₁ C₁ E₂ n₂ d₂ C₂ h1 h2 flux snell =
  trans (Sxy-flux-form E₁ n₁ d₁ C₁ h1)
        (trans (cong₂ _*_ flux snell) (sym (Sxy-flux-form E₂ n₂ d₂ C₂ h2)))

-- In every depth of a `TanhModel` the tensor is positive semi-definite.
module _ (M : TanhModel) (W : Medium) where
  open Medium W

  stress-psd : ∀ E d {k} → 0ℚ ≤ E → 0ℚ < k →
    0ℚ ≤ Sxx E (nFactor M W (k * h)) d × 0ℚ ≤ Syy E (nFactor M W (k * h)) d
    × 0ℚ ≤ Sxx E (nFactor M W (k * h)) d * Syy E (nFactor M W (k * h)) d
           - Sxy E (nFactor M W (k * h)) d * Sxy E (nFactor M W (k * h)) d
  stress-psd E d {k} hE hk =
    Sxx-nonneg E n d hE hn , Syy-nonneg E n d hE hn , stress-det-nonneg E n d hn
    where
    n  = nFactor M W (k * h)
    hn = nFactor-ge-half M W (*-pos hk h-pos)
