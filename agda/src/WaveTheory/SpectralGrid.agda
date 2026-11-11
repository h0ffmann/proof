{-# OPTIONS --safe --without-K #-}

-- The spectral grid of WAVEWATCH III: a geometric frequency grid, its integration weights, and
-- a directional spreading of a frequency spectrum. New: the Lean original has a uniform grid.
--
-- WAVEWATCH III builds the radian frequencies as a geometric sequence with the ratio XFR, and
-- gives each bin a width for the frequency integrals (model/src/w3gridmd.F90, lines 1314-1327,
-- NOAA-EMC/WW3 develop at commit dea641c, read 2026-11-11):
--
--     SIG(IK)  = SIG(1) XFR^(IK-1)
--     DSIP(IK) = SIG(IK) (XFR - 1/XFR) / 2                     (every bin)
--     DSII(1)  = SIG(1) (XFR - 1) / 2,   DSII(NK) = SIG(NK) (XFR - 1) / (2 XFR)
--     DSII(IK) = DSIP(IK)                                      (2 ≤ IK ≤ NK - 1)
--
-- Here the index starts at 0 and the grid has m + 2 bins, so the last bin is m + 1.
--
-- What this module proves:
--
-- * the grid is positive and strictly increasing when XFR > 1;
-- * an interior width is half the distance between the two neighbours, and the end widths are
--   half the distance to the one neighbour;
-- * so the widths DSII add up to exactly SIG(NK) - SIG(1), for every NK ≥ 2 and every XFR > 0
--   (`dsii-total`): the frequency integrals of WAVEWATCH III use a closed rule over the band;
-- * a geometric grid with XFR ≠ 1 is never arithmetic: σ(i) + σ(i+2) > 2 σ(i+1)
--   (`geometric-not-arithmetic`). `OceanWaves.Sources.snl-conserves-energy` needs the
--   arithmetic condition, so on a geometric grid the reduced DIA keeps the action but not the
--   energy. WAVEWATCH III's DIA interpolates to the off-grid frequencies for this reason;
--   that interpolation is not modelled here;
-- * a normalised directional spreading keeps the frequency spectrum and the total energy.
module WaveTheory.SpectralGrid where

open import Data.Bool using (true; false; if_then_else_)
open import Data.Nat as ℕ using (ℕ; zero; suc)
import Data.Nat.Properties as ℕP
open import Data.Product using (_×_; _,_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; _≤_; _<_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; <⇒≤; <-trans; <-cmp; *-identityʳ; *-zeroʳ; *-zeroˡ;
         +-identityʳ; <-irrefl; +-monoˡ-<; +-inverseʳ; neg-antimono-<; +-comm)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary using (tri<; tri≈; tri>)
open import Relation.Nullary using (contradiction)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst)

open import OceanWaves.Order
open import OceanWaves.Sums

-- ---------------------------------------------------------------------------------------------
-- The geometric grid

-- σ(i) = σ₀ rⁱ (SIG(IK) with IK = i + 1, r = XFR).
sig : ℚ → ℚ → ℕ → ℚ
sig s0 r zero    = s0
sig s0 r (suc i) = sig s0 r i * r

sig-pos : ∀ {s0 r} → 0ℚ < s0 → 0ℚ < r → ∀ i → 0ℚ < sig s0 r i
sig-pos h0 hr zero    = h0
sig-pos h0 hr (suc i) = *-pos (sig-pos h0 hr i) hr

-- r - 1 > 0 when r > 1.
gap1 : ∀ {r} → 1ℚ < r → 0ℚ < r - 1ℚ
gap1 {r} h = subst (_< r - 1ℚ) (+-inverseʳ 1ℚ) (+-monoˡ-< (- 1ℚ) h)

-- A ratio above 1 makes the grid strictly increasing.
sig-step : ∀ {s0 r} → 0ℚ < s0 → 1ℚ < r → ∀ i → sig s0 r i < sig s0 r (suc i)
sig-step {s0} {r} h0 hr i =
  by-diff< {a = σ} {b = σ * r} (σ * (r - 1ℚ))
    (solve 2 (λ s r → s :* r :- s := s :* (r :- con 1ℚ)) refl σ r)
    (*-pos (sig-pos h0 (<-trans 0<1 hr) i) (gap1 hr))
  where
  σ = sig s0 r i

-- The grid is increasing over any number of bins.
sig-mono : ∀ {s0 r} → 0ℚ < s0 → 1ℚ < r → ∀ i k → sig s0 r i ≤ sig s0 r (k ℕ.+ i)
sig-mono h0 hr i zero    = ≤-refl
sig-mono h0 hr i (suc k) = ≤-trans (sig-mono h0 hr i k) (<⇒≤ (sig-step h0 hr (k ℕ.+ i)))

-- ---------------------------------------------------------------------------------------------
-- The widths

-- DSIP: σ (r - 1/r) / 2.
dsip : ℚ → ℚ → ℕ → ℚ
dsip s0 r i = sig s0 r i * (r - inv₀ r) /₀ 2ℚ

private
  half : ℚ
  half = inv₀ 2ℚ

  two-half : 2ℚ * half ≡ 1ℚ
  two-half = inv₀-inverse 2ℚ (<⇒≢0 0<2)

  -- r · (1/r) = 1 for r ≠ 0, in the form the solver leaves.
  rv : ∀ {r} → r ≢ 0ℚ → r * inv₀ r ≡ 1ℚ
  rv {r} = inv₀-inverse r

-- An interior width is half the distance between its two neighbours.
dsip-neighbours : ∀ s0 {r} → r ≢ 0ℚ → ∀ i →
  dsip s0 r (suc i) ≡ (sig s0 r (suc (suc i)) - sig s0 r i) /₀ 2ℚ
dsip-neighbours s0 {r} r≢0 i =
  cong (_* half) (trans
    (solve 3 (λ s r v → s :* r :* (r :- v) := s :* r :* r :- s :* (r :* v)) refl σ r (inv₀ r))
    (trans (cong (λ x → σ * r * r - σ * x) (rv r≢0)) (cong (λ x → σ * r * r - x) (*-identityʳ σ))))
  where
  σ = sig s0 r i

-- DSII, for a grid of m + 2 bins: the end bins have a one-sided width.
dsii : ℕ → ℚ → ℚ → ℕ → ℚ
dsii m s0 r zero    = sig s0 r 0 * (r - 1ℚ) /₀ 2ℚ
dsii m s0 r (suc i) =
  if i ℕ.≡ᵇ m then sig s0 r (suc m) * (r - 1ℚ) * inv₀ r /₀ 2ℚ else dsip s0 r (suc i)

dsii-first : ∀ m s0 r → dsii m s0 r 0 ≡ (sig s0 r 1 - sig s0 r 0) /₀ 2ℚ
dsii-first m s0 r = cong (_* half) (solve 2 (λ s r → s :* (r :- con 1ℚ) := s :* r :- s) refl s0 r)

private
  ≡ᵇ-refl : ∀ m → (m ℕ.≡ᵇ m) ≡ true
  ≡ᵇ-refl m with m ℕ.≡ᵇ m in eq
  ... | true  = refl
  ... | false = contradiction refl (eqb-false {m} {m} eq)

  ≡ᵇ-below : ∀ {i m} → i ℕ.< m → (i ℕ.≡ᵇ m) ≡ false
  ≡ᵇ-below {i} {m} i<m with i ℕ.≡ᵇ m in eq
  ... | true  = contradiction (eqb-true {i} {m} eq) (ℕP.<⇒≢ i<m)
  ... | false = refl

dsii-last : ∀ m s0 {r} → r ≢ 0ℚ →
  dsii m s0 r (suc m) ≡ (sig s0 r (suc m) - sig s0 r m) /₀ 2ℚ
dsii-last m s0 {r} r≢0 rewrite ≡ᵇ-refl m =
  cong (_* half) (trans
    (solve 3 (λ s r v → s :* r :* (r :- con 1ℚ) :* v := s :* r :* (r :* v) :- s :* (r :* v))
      refl σ r (inv₀ r))
    (trans (cong (λ x → σ * r * x - σ * x) (rv r≢0))
           (cong₂ _-_ (*-identityʳ (σ * r)) (*-identityʳ σ))))
  where
  σ = sig s0 r m

dsii-interior : ∀ m s0 r i → i ℕ.< m → dsii m s0 r (suc i) ≡ dsip s0 r (suc i)
dsii-interior m s0 r i i<m rewrite ≡ᵇ-below i<m = refl

-- A sum of second differences keeps four end values.
sumTo-second-diff : ∀ n (f : ℕ → ℚ) →
  sumTo n (λ i → f (suc (suc i)) - f i) ≡ f (suc n) + f n - f 1 - f 0
sumTo-second-diff zero    f =
  solve 2 (λ a b → con 0ℚ := b :+ a :- b :- a) refl (f 0) (f 1)
sumTo-second-diff (suc n) f rewrite sumTo-second-diff n f =
  solve 5 (λ a b x y z → (z :+ y :- b :- a) :+ (x :- y) := x :+ z :- b :- a) refl
    (f 0) (f 1) (f (suc (suc n))) (f n) (f (suc n))

-- The widths add up to the band: Σ DSII = SIG(NK) - SIG(1), for every grid of two or more bins.
dsii-total : ∀ m s0 {r} → r ≢ 0ℚ →
  sumTo (suc (suc m)) (dsii m s0 r) ≡ sig s0 r (suc m) - sig s0 r 0
dsii-total m s0 {r} r≢0 =
  begin-eq
  where
  σ = sig s0 r
  interior : sumTo m (λ i → dsii m s0 r (suc i))
           ≡ (σ (suc m) + σ m - σ 1 - σ 0) * half
  interior =
    trans (sumTo-congr m _ _ (λ i i<m → trans (dsii-interior m s0 r i i<m) (dsip-neighbours s0 r≢0 i)))
    (trans (sumTo-mul-right m half)
           (cong (_* half) (sumTo-second-diff m σ)))
    where
    sumTo-mul-right : ∀ n c → sumTo n (λ i → (σ (suc (suc i)) - σ i) * c)
                    ≡ sumTo n (λ i → σ (suc (suc i)) - σ i) * c
    sumTo-mul-right zero    c = sym (*-zeroˡ c)
    sumTo-mul-right (suc n) c rewrite sumTo-mul-right n c =
      solve 3 (λ s x c → s :* c :+ x :* c := (s :+ x) :* c) refl
        (sumTo n (λ i → σ (suc (suc i)) - σ i)) (σ (suc (suc n)) - σ n) c
  begin-eq : sumTo (suc (suc m)) (dsii m s0 r) ≡ σ (suc m) - σ 0
  begin-eq =
    trans (cong (_+ dsii m s0 r (suc m)) (sumTo-succ-left m (dsii m s0 r)))
    (trans (cong₂ (λ x y → (x + sumTo m (λ i → dsii m s0 r (suc i))) + y)
                  (dsii-first m s0 r) (dsii-last m s0 r≢0))
    (trans (cong (λ x → ((σ 1 - σ 0) * half + x) + (σ (suc m) - σ m) * half) interior)
    (trans (solve 5 (λ a b x y h →
              (b :- a) :* h :+ (x :+ y :- b :- a) :* h :+ (x :- y) :* h
              := (x :- a) :* ((con 1ℚ :+ con 1ℚ) :* h)) refl
              (σ 0) (σ 1) (σ (suc m)) (σ m) half)
    (trans (cong ((σ (suc m) - σ 0) *_) two-half) (*-identityʳ _)))))

-- Every width is positive when r > 1.
dsii-pos : ∀ m {s0 r} → 0ℚ < s0 → 1ℚ < r → ∀ i → 0ℚ < dsii m s0 r i
dsii-pos m {s0} {r} h0 hr zero = div-pos (*-pos h0 (gap1 hr)) 0<2
dsii-pos m {s0} {r} h0 hr (suc i) with i ℕ.≡ᵇ m
... | true  = div-pos (*-pos (*-pos (sig-pos h0 0<r (suc m)) (gap1 hr)) (inv₀-pos 0<r)) 0<2
  where
  0<r = <-trans 0<1 hr
... | false = div-pos (*-pos (sig-pos h0 0<r (suc i)) r-v>0) 0<2
  where
  0<r = <-trans 0<1 hr
  rr-1>0 : 0ℚ < r * r - 1ℚ
  rr-1>0 = subst (_< r * r - 1ℚ) (+-inverseʳ 1ℚ)
             (+-monoˡ-< (- 1ℚ) (<-trans hr (lt-sq hr)))
    where
    -- r < r · r for r > 1.
    lt-sq : 1ℚ < r → r < r * r
    lt-sq h = by-diff< {a = r} {b = r * r} (r * (r - 1ℚ))
                (solve 1 (λ r → r :* r :- r := r :* (r :- con 1ℚ)) refl r)
                (*-pos 0<r (gap1 h))
  r-v>0 : 0ℚ < r - inv₀ r
  r-v>0 = subst (0ℚ <_)
            (trans (solve 2 (λ r v → (r :* r :- con 1ℚ) :* v := r :* (r :* v) :- v) refl r (inv₀ r))
                   (cong (λ x → r * x - inv₀ r) (rv (<⇒≢0 0<r)) ⟨≡⟩ cong (_- inv₀ r) (*-identityʳ r)))
            (*-pos rr-1>0 (inv₀-pos 0<r))
    where _⟨≡⟩_ = trans

-- ---------------------------------------------------------------------------------------------
-- A geometric grid is not arithmetic

-- The second difference of the grid is σ(i) (r - 1)².
sig-second-diff : ∀ s0 r i →
  sig s0 r i + sig s0 r (suc (suc i)) - 2ℚ * sig s0 r (suc i) ≡ sig s0 r i * ((r - 1ℚ) * (r - 1ℚ))
sig-second-diff s0 r i =
  solve 2 (λ s r → s :+ s :* r :* r :- (con 1ℚ :+ con 1ℚ) :* (s :* r)
                   := s :* ((r :- con 1ℚ) :* (r :- con 1ℚ))) refl (sig s0 r i) r

-- With r ≠ 1 the two neighbours always add up to more than twice the middle value.
geometric-not-arithmetic : ∀ {s0 r} → 0ℚ < s0 → 0ℚ < r → r ≢ 1ℚ → ∀ i →
  2ℚ * sig s0 r (suc i) < sig s0 r i + sig s0 r (suc (suc i))
geometric-not-arithmetic {s0} {r} h0 hr r≢1 i =
  by-diff< {a = 2ℚ * sig s0 r (suc i)} {b = sig s0 r i + sig s0 r (suc (suc i))}
    (sig s0 r i * ((r - 1ℚ) * (r - 1ℚ))) (sig-second-diff s0 r i)
    (*-pos (sig-pos h0 hr i) sq-pos)
  where
  d = r - 1ℚ
  sq-pos : 0ℚ < d * d
  sq-pos with <-cmp d 0ℚ
  ... | tri< d<0 _ _ =
    subst (0ℚ <_) (solve 1 (λ d → (:-′ d) :* (:-′ d) := d :* d) refl d)
      (*-pos neg-pos neg-pos)
    where
    open +-*-Solver using () renaming (:-_ to :-′_)
    neg-pos : 0ℚ < - d
    neg-pos = neg-antimono-< d<0
  ... | tri≈ _ d≡0 _ = contradiction r≡1 r≢1
    where
    r≡1 : r ≡ 1ℚ
    r≡1 = trans (solve 1 (λ r → r := (r :- con 1ℚ) :+ con 1ℚ) refl r)
                (trans (cong (_+ 1ℚ) d≡0) refl)
  ... | tri> _ _ d>0 = *-pos d>0 d>0

-- ---------------------------------------------------------------------------------------------
-- Directional spreading

-- A directional distribution over nth directions: non-negative, and its weights add up to 1.
record Spreading (nth : ℕ) : Set where
  field
    D        : ℕ → ℚ
    D-nonneg : ∀ j → j ℕ.< nth → 0ℚ ≤ D j
    D-sum    : sumTo nth D ≡ 1ℚ
open Spreading public

-- F(i, j) = E(i) D(j): a frequency spectrum spread over the directions.
spread : ∀ {nth} → Spreading nth → (ℕ → ℚ) → ℕ → ℕ → ℚ
spread S E i j = E i * D S j

-- The directional sum of the spread spectrum gives the frequency spectrum back.
spread-recovers : ∀ {nth} (S : Spreading nth) E i → sumTo nth (spread S E i) ≡ E i
spread-recovers {nth} S E i =
  trans (sumTo-mul-left nth (E i) (D S)) (trans (cong (E i *_) (D-sum S)) (*-identityʳ (E i)))

-- So the total energy over the 2-D grid is the total of the frequency spectrum.
spread-total : ∀ {nth} (S : Spreading nth) E nk →
  sumTo nk (λ i → sumTo nth (spread S E i)) ≡ sumTo nk E
spread-total S E nk = sumTo-congr nk _ _ (λ i _ → spread-recovers S E i)

spread-nonneg : ∀ {nth} (S : Spreading nth) E i j → 0ℚ ≤ E i → j ℕ.< nth → 0ℚ ≤ spread S E i j
spread-nonneg S E i j hE hj = *-nonneg hE (D-nonneg S j hj)

-- n as a rational, counted one by one, so that sums of a constant reduce.
count : ℕ → ℚ
count zero    = 0ℚ
count (suc n) = count n + 1ℚ

count-pos : ∀ n → 0ℚ < count (suc n)
count-pos n = +-pos′ (count-nonneg n)
  where
  count-nonneg : ∀ n → 0ℚ ≤ count n
  count-nonneg zero    = ≤-refl
  count-nonneg (suc n) = +-nonneg (count-nonneg n) (<⇒≤ 0<1)
  +-pos′ : ∀ {a} → 0ℚ ≤ a → 0ℚ < a + 1ℚ
  +-pos′ {a} ha = subst (0ℚ <_) (+-comm 1ℚ a) (+-pos 0<1 ha)

sumTo-const : ∀ n c → sumTo n (λ _ → c) ≡ count n * c
sumTo-const zero    c = sym (*-zeroˡ c)
sumTo-const (suc n) c rewrite sumTo-const n c =
  solve 2 (λ k c → k :* c :+ c := (k :+ con 1ℚ) :* c) refl (count n) c

-- The isotropic spreading: the same weight 1/nth in each of nth ≥ 1 directions.
isotropic : ∀ n → Spreading (suc n)
isotropic n = record
  { D        = λ _ → inv₀ (count (suc n))
  ; D-nonneg = λ _ _ → <⇒≤ (inv₀-pos (count-pos n))
  ; D-sum    = trans (sumTo-const (suc n) _) (inv₀-inverse _ (<⇒≢0 (count-pos n)))
  }
