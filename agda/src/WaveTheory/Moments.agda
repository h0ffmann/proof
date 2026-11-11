{-# OPTIONS --safe --without-K #-}

-- Spectral moments of a discrete wave spectrum, the significant wave height and the
-- Cauchy-Schwarz bound between the moments. New: the Lean original has no moments.
--
-- A discrete spectrum has n bins. Bin i has the radian frequency σ i and the energy E i (the
-- variance density times the bin width, so the sums below are the quadrature that WAVEWATCH
-- III uses for its integral parameters). The moment of order p is
--
--     m_p = Σ_i σ_i^p E_i.
--
-- ℚ has no square root, so the significant wave height is kept squared:
-- H_s² = H_m0² = 16 m_0. Every statement here is about finite sums of exact rationals; none is
-- about an integral over a continuous spectrum.
module WaveTheory.Moments where

open import Data.Nat as ℕ using (ℕ; zero; suc)
import Data.Nat.Properties as ℕP
open import Data.Product using (_×_; _,_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _<_)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; +-mono-≤; *-monoˡ-≤-nonNeg; *-monoʳ-≤-nonNeg)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong; cong₂; subst)

open import OceanWaves.Order
open import OceanWaves.Sums
open import WaveTheory.Algebra

-- ---------------------------------------------------------------------------------------------
-- Moments

-- m_p of the first n bins.
moment : ℕ → ℕ → (σ E : ℕ → ℚ) → ℚ
moment p n σ E = sumTo n (λ i → pow (σ i) p * E i)

-- The three moments that the integral parameters use, in the form the proofs use.
m0 m1 m2 : ℕ → (σ E : ℕ → ℚ) → ℚ
m0 n σ E = sumTo n E
m1 n σ E = sumTo n (λ i → σ i * E i)
m2 n σ E = sumTo n (λ i → σ i * σ i * E i)

moment-0 : ∀ n σ E → moment 0 n σ E ≡ m0 n σ E
moment-0 n σ E = sumTo-congr n _ _ (λ i _ → solve 1 (λ e → con 1ℚ :* e := e) refl (E i))

moment-1 : ∀ n σ E → moment 1 n σ E ≡ m1 n σ E
moment-1 n σ E = sumTo-congr n _ _ (λ i _ → solve 2 (λ s e → s :* con 1ℚ :* e := s :* e) refl (σ i) (E i))

moment-2 : ∀ n σ E → moment 2 n σ E ≡ m2 n σ E
moment-2 n σ E =
  sumTo-congr n _ _ (λ i _ → solve 2 (λ s e → s :* (s :* con 1ℚ) :* e := s :* s :* e) refl (σ i) (E i))

-- A spectrum with no negative energy.
NonNeg : ℕ → (ℕ → ℚ) → Set
NonNeg n E = ∀ i → i ℕ.< n → 0ℚ ≤ E i

-- Every even moment of a non-negative spectrum is non-negative, and so is every moment when
-- the frequencies are non-negative.
moment-nonneg : ∀ p n σ E → (∀ i → i ℕ.< n → 0ℚ ≤ σ i) → NonNeg n E → 0ℚ ≤ moment p n σ E
moment-nonneg p n σ E hσ hE = sumTo-nonneg n _ (λ i hi → *-nonneg (pow-nonneg p (hσ i hi)) (hE i hi))
  where
  pow-nonneg : ∀ q {x} → 0ℚ ≤ x → 0ℚ ≤ pow x q
  pow-nonneg zero    hx = <⇒≤ 0<1
    where open import Data.Rational.Properties using (<⇒≤)
  pow-nonneg (suc q) hx = *-nonneg hx (pow-nonneg q hx)

-- Moments are linear in the spectrum: the moment of a sum of two seas (a wind sea and a
-- swell) is the sum of their moments.
moment-add : ∀ p n σ E F → moment p n σ (λ i → E i + F i) ≡ moment p n σ E + moment p n σ F
moment-add p n σ E F =
  trans (sumTo-congr n _ (λ i → pow (σ i) p * E i + pow (σ i) p * F i)
           (λ i _ → solve 3 (λ s e f → s :* (e :+ f) := s :* e :+ s :* f) refl (pow (σ i) p) (E i) (F i)))
        (sumTo-add n _ _)

moment-scale : ∀ p n σ E r → moment p n σ (λ i → r * E i) ≡ r * moment p n σ E
moment-scale p n σ E r =
  trans (sumTo-congr n _ (λ i → r * (pow (σ i) p * E i))
           (λ i _ → solve 3 (λ s r e → s :* (r :* e) := r :* (s :* e)) refl (pow (σ i) p) r (E i)))
        (sumTo-mul-left n r _)

-- A larger spectrum, bin by bin, has larger moments.
moment-mono : ∀ p n σ E F → (∀ i → i ℕ.< n → 0ℚ ≤ σ i) → (∀ i → i ℕ.< n → E i ≤ F i) →
  moment p n σ E ≤ moment p n σ F
moment-mono p n σ E F hσ h =
  sumTo-mono n _ _ (λ i hi → *-monoˡ-≤-nonNeg (pow (σ i) p) {{nonNegative (pn p (hσ i hi))}} (h i hi))
  where
  open import Data.Rational.Properties using (<⇒≤)
  pn : ∀ q {x} → 0ℚ ≤ x → 0ℚ ≤ pow x q
  pn zero    hx = <⇒≤ 0<1
  pn (suc q) hx = *-nonneg hx (pn q hx)

-- ---------------------------------------------------------------------------------------------
-- Significant wave height

-- H_s² = 16 m_0 (H_m0 = 4 √m_0).
hs2 : ℕ → (σ E : ℕ → ℚ) → ℚ
hs2 n σ E = lit 16 * m0 n σ E

hs2-nonneg : ∀ n σ E → NonNeg n E → 0ℚ ≤ hs2 n σ E
hs2-nonneg n σ E hE = *-nonneg (<⇒≤ (from-yes (0ℚ <? lit 16))) (sumTo-nonneg n E hE)
  where
  open import Data.Rational using (_<?_)
  open import Data.Rational.Properties using (<⇒≤)
  open import Relation.Nullary.Decidable using (from-yes)

-- Two seas that share the spectral grid: H_s² of the total sea is the sum of the two H_s²,
-- so H_s = √(H_s,wind² + H_s,swell²).
hs2-superpose : ∀ n σ E F → hs2 n σ (λ i → E i + F i) ≡ hs2 n σ E + hs2 n σ F
hs2-superpose n σ E F =
  trans (cong (lit 16 *_) (sumTo-add n E F))
        (solve 3 (λ c a b → c :* (a :+ b) := c :* a :+ c :* b) refl (lit 16) (m0 n σ E) (m0 n σ F))

-- More energy in every bin gives a higher sea.
hs2-mono : ∀ n σ E F → (∀ i → i ℕ.< n → E i ≤ F i) → hs2 n σ E ≤ hs2 n σ F
hs2-mono n σ E F h =
  *-monoˡ-≤-nonNeg (lit 16) {{nonNegative (<⇒≤ (from-yes (0ℚ <? lit 16)))}} (sumTo-mono n E F h)
  where
  open import Data.Rational using (_<?_)
  open import Data.Rational.Properties using (<⇒≤)
  open import Relation.Nullary.Decidable using (from-yes)

-- ---------------------------------------------------------------------------------------------
-- The mean frequency lies in the band

-- If every frequency is in [lo, hi], then lo m_0 ≤ m_1 ≤ hi m_0. So the mean frequency
-- m_1 / m_0 (WAVEWATCH III's FM01) lies in the band.
m1-in-band : ∀ n σ E lo hi → NonNeg n E → (∀ i → i ℕ.< n → lo ≤ σ i × σ i ≤ hi) →
  lo * m0 n σ E ≤ m1 n σ E × m1 n σ E ≤ hi * m0 n σ E
m1-in-band n σ E lo hi hE hb =
  ≤-trans (≤-reflexive (sym (sumTo-mul-left n lo E)))
          (sumTo-mono n _ _ (λ i hi′ → *-monoʳ-≤-nonNeg (E i) {{nonNegative (hE i hi′)}} (proj₁ (hb i hi′)))) ,
  ≤-trans (sumTo-mono n _ _ (λ i hi′ → *-monoʳ-≤-nonNeg (E i) {{nonNegative (hE i hi′)}} (proj₂ (hb i hi′))))
          (≤-reflexive (sumTo-mul-left n hi E))
  where open import Data.Product using (proj₁; proj₂)

-- ---------------------------------------------------------------------------------------------
-- Cauchy-Schwarz: m_1² ≤ m_0 m_2

-- The spread of the spectrum around a frequency a: Σ E_i (a - σ_i)² = a² m_0 - 2 a m_1 + m_2.
spread : ℕ → (σ E : ℕ → ℚ) → ℚ → ℚ
spread n σ E a = sumTo n (λ i → E i * ((a - σ i) * (a - σ i)))

spread-eq : ∀ n σ E a → spread n σ E a ≡ a * a * m0 n σ E - 2ℚ * a * m1 n σ E + m2 n σ E
spread-eq zero    σ E a = solve 1 (λ a → con 0ℚ := a :* a :* con 0ℚ :- (con 1ℚ :+ con 1ℚ) :* a :* con 0ℚ :+ con 0ℚ) refl a
spread-eq (suc n) σ E a rewrite spread-eq n σ E a =
  solve 6 (λ a s0 s1 s2 e s →
      a :* a :* s0 :- (con 1ℚ :+ con 1ℚ) :* a :* s1 :+ s2 :+ e :* ((a :- s) :* (a :- s))
      := a :* a :* (s0 :+ e) :- (con 1ℚ :+ con 1ℚ) :* a :* (s1 :+ s :* e) :+ (s2 :+ s :* s :* e))
    refl a (m0 n σ E) (m1 n σ E) (m2 n σ E) (E n) (σ n)

spread-nonneg : ∀ n σ E a → NonNeg n E → 0ℚ ≤ spread n σ E a
spread-nonneg n σ E a hE = sumTo-nonneg n _ (λ i hi → *-nonneg (hE i hi) (sq-nonneg (a - σ i)))

-- The discrete Cauchy-Schwarz inequality for a non-negative spectrum. It is proved by
-- induction on the number of bins: a new bin (w, b) adds w · spread(b) ≥ 0 to m_0 m_2 - m_1².
cauchy-schwarz : ∀ n σ E → NonNeg n E → m1 n σ E * m1 n σ E ≤ m0 n σ E * m2 n σ E
cauchy-schwarz zero    σ E hE = ≤-refl
cauchy-schwarz (suc n) σ E hE =
  by-diff (D + w * spread n σ E b)
    (trans (solve 6 (λ s0 s1 s2 w b sp →
              (s0 :+ w) :* (s2 :+ b :* b :* w) :- (s1 :+ b :* w) :* (s1 :+ b :* w)
              := (s0 :* s2 :- s1 :* s1) :+ w :* (b :* b :* s0 :- (con 1ℚ :+ con 1ℚ) :* b :* s1 :+ s2))
              refl S0 S1 S2 w b (spread n σ E b))
           (cong (λ u → D + w * u) (sym (spread-eq n σ E b))))
    (+-nonneg (≤⇒0≤- (cauchy-schwarz n σ E (λ i hi → hE i (ℕP.m<n⇒m<1+n hi))))
              (*-nonneg (hE n (ℕP.n<1+n n)) (spread-nonneg n σ E b (λ i hi → hE i (ℕP.m<n⇒m<1+n hi)))))
  where
  S0 = m0 n σ E
  S1 = m1 n σ E
  S2 = m2 n σ E
  w  = E n
  b  = σ n
  D  = S0 * S2 - S1 * S1

-- The spectral width ν² = m_0 m_2 / m_1² - 1 (Longuet-Higgins 1975) is never negative. In the
-- cross-multiplied form: m_0 m_2 - m_1² ≥ 0. It is zero for a single bin.
width-nonneg : ∀ n σ E → NonNeg n E → 0ℚ ≤ m0 n σ E * m2 n σ E - m1 n σ E * m1 n σ E
width-nonneg n σ E hE = ≤⇒0≤- (cauchy-schwarz n σ E hE)

width-one-bin : ∀ σ E → m0 1 σ E * m2 1 σ E - m1 1 σ E * m1 1 σ E ≡ 0ℚ
width-one-bin σ E =
  solve 2 (λ s e → (con 0ℚ :+ e) :* (con 0ℚ :+ s :* s :* e) :- (con 0ℚ :+ s :* e) :* (con 0ℚ :+ s :* e) := con 0ℚ)
    refl (σ 0) (E 0)
