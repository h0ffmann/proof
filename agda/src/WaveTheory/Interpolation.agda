{-# OPTIONS --safe --without-K #-}

-- Linear interpolation weights for the off-grid frequencies of the discrete interaction
-- approximation (DIA), and the budgets that they keep. New: the Lean original has no DIA
-- interpolation.
--
-- The DIA couples a component at σ with the components at σ (1 + λ) and σ (1 - λ). On a
-- geometric grid these two frequencies are not grid values. So the model gives the quartet's
-- contribution at an off-grid point x to the two grid values a < b that bracket it, with the
-- linear weights
--
--     wa = (b - x) / (b - a),    wb = (x - a) / (b - a).
--
-- The DIA is from Hasselmann et al. (1985), doi:10.1175/1520-0485(1985)015<1378:CAPOTN>2.0.CO;2.
-- Here only the interpolation step is modelled, not the quartet itself.
--
-- What this module proves, for a < b:
--
-- * wa + wb = 1 (`weights-sum`), so an action amount A given as wa A and wb A keeps the action
--   exactly (`action-split`);
-- * 0 ≤ wa ≤ 1 and 0 ≤ wb ≤ 1 when a ≤ x ≤ b (`wa-nonneg`, `wa-le-one`, `wb-nonneg`,
--   `wb-le-one`);
-- * wa a + wb b = x (`interp-freq`), so the energy σ A is kept when the interpolated
--   frequency carries it: (wa A) a + (wb A) b = A x (`energy-split`);
-- * the interpolation of a linear function p + q y is exact (`linear-exact`);
-- * for the convex function y², the interpolation is too large:
--   wa a² + wb b² - x² = wa wb (b - a)² (`convex-gap`), so x² ≤ wa a² + wb b²
--   (`convex-over`), with a strict inequality inside the bin (`convex-strict`) and an
--   equality at the two ends (`convex-end-lo`, `convex-end-hi`);
-- * a list of amounts, each given to two bins of a discrete field ℕ → ℚ, keeps the total
--   action when every target bin is below n and each pair of weights adds to 1
--   (`spread-total`); the energy Σ g(k) F(k) is the sum of A (wlo g(lo) + whi g(hi))
--   (`spread-energy`), which is A x for an interpolation share (`share-energy`);
-- * bilinear weights over frequency and direction: the four weights add to 1
--   (`bilinear-sum`), they are not negative (`bilinear-nonneg`), and they give back both
--   coordinates (`bilinear-freq`, `bilinear-dir`).
--
-- Premises and limits: the weights use the total division `_/₀_`, so every statement takes
-- a < b (when a = b all the weights are 0). The quadratic result shows that the interpolation
-- does not keep a quantity that is quadratic in the frequency. Only the action and the
-- linear energy σ A are kept.
module WaveTheory.Interpolation where

open import Data.Bool using (true; false)
open import Data.List using (List; []; _∷_)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.Nat as ℕ using (ℕ; suc)
open import Data.Product using (_×_; _,_)
open import Data.Integer using () renaming (+_ to ℤ+)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _/_; _+_; _-_; _*_; _≤_; _<_; _≤?_; _<?_)
open import Data.Rational.Properties
  using (≤-trans; <⇒≤; *-identityˡ; *-identityʳ; *-zeroʳ; *-distribˡ-+)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Nullary.Decidable using (from-yes)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst)

open import OceanWaves.Order
open import OceanWaves.Sums

-- ---------------------------------------------------------------------------------------------
-- The two weights

-- The weight of the lower grid value a.
wa : ℚ → ℚ → ℚ → ℚ
wa a b x = (b - x) /₀ (b - a)

-- The weight of the upper grid value b.
wb : ℚ → ℚ → ℚ → ℚ
wb a b x = (x - a) /₀ (b - a)

private
  inv-bin : ∀ {a b} → a < b → (b - a) * inv₀ (b - a) ≡ 1ℚ
  inv-bin {a} {b} h = inv₀-inverse (b - a) (<⇒≢0 (<⇒0<- h))

  -- From u + v = 1: v = 1 - u.
  other : ∀ u v → u + v ≡ 1ℚ → v ≡ 1ℚ - u
  other u v e = trans (solve 2 (λ u v → v := (u :+ v) :- u) refl u v) (cong (_- u) e)

-- The two weights add to 1.
weights-sum : ∀ {a b} x → a < b → wa a b x + wb a b x ≡ 1ℚ
weights-sum {a} {b} x h =
  trans (solve 4 (λ a b x i → (b :- x) :* i :+ (x :- a) :* i := (b :- a) :* i)
           refl a b x (inv₀ (b - a)))
        (inv-bin h)

-- Two weights that add to 1 keep an amount.
split-keeps : ∀ u v A → u + v ≡ 1ℚ → u * A + v * A ≡ A
split-keeps u v A e =
  trans (solve 3 (λ u v A → u :* A :+ v :* A := (u :+ v) :* A) refl u v A)
        (trans (cong (_* A) e) (*-identityˡ A))

-- The action is kept: wa A + wb A = A.
action-split : ∀ {a b} x A → a < b → wa a b x * A + wb a b x * A ≡ A
action-split {a} {b} x A h = split-keeps (wa a b x) (wb a b x) A (weights-sum x h)

-- The weights reproduce the off-grid point: wa a + wb b = x.
interp-freq : ∀ {a b} x → a < b → wa a b x * a + wb a b x * b ≡ x
interp-freq {a} {b} x h =
  trans (solve 4 (λ a b x i → (b :- x) :* i :* a :+ (x :- a) :* i :* b := x :* ((b :- a) :* i))
           refl a b x (inv₀ (b - a)))
        (trans (cong (x *_) (inv-bin h)) (*-identityʳ x))

-- The energy σ A is kept: (wa A) a + (wb A) b = A x.
energy-split : ∀ {a b} x A → a < b → (wa a b x * A) * a + (wb a b x * A) * b ≡ A * x
energy-split {a} {b} x A h =
  trans (solve 5 (λ p q A a b → (p :* A) :* a :+ (q :* A) :* b := A :* (p :* a :+ q :* b))
           refl (wa a b x) (wb a b x) A a b)
        (cong (A *_) (interp-freq x h))

-- ---------------------------------------------------------------------------------------------
-- The weights are in [0, 1]

wa-nonneg : ∀ {a b x} → a ≤ x → x ≤ b → 0ℚ ≤ wa a b x
wa-nonneg ax xb = div-nonneg (≤⇒0≤- xb) (≤⇒0≤- (≤-trans ax xb))

wb-nonneg : ∀ {a b x} → a ≤ x → x ≤ b → 0ℚ ≤ wb a b x
wb-nonneg ax xb = div-nonneg (≤⇒0≤- ax) (≤⇒0≤- (≤-trans ax xb))

wa-le-one : ∀ {a b x} → a < b → a ≤ x → x ≤ b → wa a b x ≤ 1ℚ
wa-le-one {a} {b} {x} h ax xb =
  by-diff (wb a b x)
    (trans (cong (_- wa a b x) (sym (weights-sum x h)))
           (solve 2 (λ p q → (p :+ q) :- p := q) refl (wa a b x) (wb a b x)))
    (wb-nonneg ax xb)

wb-le-one : ∀ {a b x} → a < b → a ≤ x → x ≤ b → wb a b x ≤ 1ℚ
wb-le-one {a} {b} {x} h ax xb =
  by-diff (wa a b x)
    (trans (cong (_- wb a b x) (sym (weights-sum x h)))
           (solve 2 (λ p q → (p :+ q) :- q := p) refl (wa a b x) (wb a b x)))
    (wa-nonneg ax xb)

-- ---------------------------------------------------------------------------------------------
-- Linear and quadratic functions

-- The interpolation of p + q y is exact.
linear-exact : ∀ {a b} x p q → a < b →
  wa a b x * (p + q * a) + wb a b x * (p + q * b) ≡ p + q * x
linear-exact {a} {b} x p q h =
  trans (solve 6 (λ u v a b p q →
           u :* (p :+ q :* a) :+ v :* (p :+ q :* b) := (u :+ v) :* p :+ q :* (u :* a :+ v :* b))
           refl (wa a b x) (wb a b x) a b p q)
        (trans (cong₂ (λ s y → s * p + q * y) (weights-sum x h) (interp-freq x h))
               (cong (_+ q * x) (*-identityˡ p)))

-- For any two weights that add to 1, the interpolation of y² exceeds the square of the
-- interpolated point by u v (b - a)².
gap-identity : ∀ u v a b → u + v ≡ 1ℚ →
  u * (a * a) + v * (b * b) - (u * a + v * b) * (u * a + v * b) ≡ u * v * ((b - a) * (b - a))
gap-identity u v a b e =
  subst (λ w → u * (a * a) + w * (b * b) - (u * a + w * b) * (u * a + w * b)
             ≡ u * w * ((b - a) * (b - a)))
        (sym (other u v e))
        (solve 3 (λ u a b →
           u :* (a :* a) :+ (con 1ℚ :- u) :* (b :* b)
             :- (u :* a :+ (con 1ℚ :- u) :* b) :* (u :* a :+ (con 1ℚ :- u) :* b)
           := u :* (con 1ℚ :- u) :* ((b :- a) :* (b :- a))) refl u a b)

-- The convex gap: wa a² + wb b² - x² = wa wb (b - a)².
convex-gap : ∀ {a b} x → a < b →
  wa a b x * (a * a) + wb a b x * (b * b) - x * x ≡ wa a b x * wb a b x * ((b - a) * (b - a))
convex-gap {a} {b} x h =
  subst (λ y → wa a b x * (a * a) + wb a b x * (b * b) - y * y
             ≡ wa a b x * wb a b x * ((b - a) * (b - a)))
        (interp-freq x h) (gap-identity (wa a b x) (wb a b x) a b (weights-sum x h))

-- The interpolation over-estimates y²: x² ≤ wa a² + wb b².
convex-over : ∀ {a b x} → a < b → a ≤ x → x ≤ b →
  x * x ≤ wa a b x * (a * a) + wb a b x * (b * b)
convex-over {a} {b} {x} h ax xb =
  by-diff _ (convex-gap x h)
    (*-nonneg (*-nonneg (wa-nonneg ax xb) (wb-nonneg ax xb)) (sq-nonneg (b - a)))

-- Inside the bin the over-estimate is strict.
convex-strict : ∀ {a b x} → a < x → x < b →
  x * x < wa a b x * (a * a) + wb a b x * (b * b)
convex-strict {a} {b} {x} ax xb =
  by-diff< _ (convex-gap x ab)
    (*-pos (*-pos (div-pos (<⇒0<- xb) (<⇒0<- ab)) (div-pos (<⇒0<- ax) (<⇒0<- ab)))
           (*-pos (<⇒0<- ab) (<⇒0<- ab)))
  where
  open import Data.Rational.Properties using (<-trans)
  ab = <-trans ax xb

-- At the ends the interpolation of y² is exact.
convex-end-lo : ∀ {a b} → a < b → wa a b a * (a * a) + wb a b a * (b * b) ≡ a * a
convex-end-lo {a} {b} h =
  trans (cong₂ (λ p q → p * (a * a) + q * (b * b)) wa1 wb0)
        (solve 2 (λ a b → con 1ℚ :* (a :* a) :+ con 0ℚ :* (b :* b) := a :* a) refl a b)
  where
  wb0 : wb a b a ≡ 0ℚ
  wb0 = solve 2 (λ a i → (a :- a) :* i := con 0ℚ) refl a (inv₀ (b - a))
  wa1 : wa a b a ≡ 1ℚ
  wa1 = trans (solve 2 (λ p q → p := (p :+ q) :- q) refl (wa a b a) (wb a b a))
              (trans (cong₂ _-_ (weights-sum a h) wb0) refl)

convex-end-hi : ∀ {a b} → a < b → wa a b b * (a * a) + wb a b b * (b * b) ≡ b * b
convex-end-hi {a} {b} h =
  trans (cong₂ (λ p q → p * (a * a) + q * (b * b)) wa0 wb1)
        (solve 2 (λ a b → con 0ℚ :* (a :* a) :+ con 1ℚ :* (b :* b) := b :* b) refl a b)
  where
  wa0 : wa a b b ≡ 0ℚ
  wa0 = solve 2 (λ b i → (b :- b) :* i := con 0ℚ) refl b (inv₀ (b - a))
  wb1 : wb a b b ≡ 1ℚ
  wb1 = trans (other (wa a b b) (wb a b b) (weights-sum b h)) (trans (cong (1ℚ -_) wa0) refl)

-- ---------------------------------------------------------------------------------------------
-- Distribution to the bins of a discrete field

-- An amount A given to the bins lo and hi with the weights wlo and whi.
record Share : Set where
  constructor share
  field
    lo hi       : ℕ
    wlo whi amt : ℚ
open Share public

-- The part of the field that one share makes.
deposit : Share → ℕ → ℚ
deposit s k = pick (lo s) (λ _ → wlo s * amt s) k + pick (hi s) (λ _ → whi s * amt s) k

-- The field that a list of shares makes.
spread : List Share → ℕ → ℚ
spread []       k = 0ℚ
spread (s ∷ ss) k = deposit s k + spread ss k

-- The total amount given.
totalAmt : List Share → ℚ
totalAmt []       = 0ℚ
totalAmt (s ∷ ss) = amt s + totalAmt ss

-- The energy that the shares carry on the grid g: A (wlo g(lo) + whi g(hi)) for each share.
energyAmt : (ℕ → ℚ) → List Share → ℚ
energyAmt g []       = 0ℚ
energyAmt g (s ∷ ss) = amt s * (wlo s * g (lo s) + whi s * g (hi s)) + energyAmt g ss

-- Both target bins of a share are below n.
Inside : ℕ → Share → Set
Inside n s = lo s ℕ.< n × hi s ℕ.< n

-- And its weights add to 1.
Good : ℕ → Share → Set
Good n s = Inside n s × wlo s + whi s ≡ 1ℚ

deposit-sum : ∀ n s → Inside n s → sumTo n (deposit s) ≡ wlo s * amt s + whi s * amt s
deposit-sum n s (hl , hh) =
  trans (sumTo-add n (pick (lo s) (λ _ → wlo s * amt s)) (pick (hi s) (λ _ → whi s * amt s)))
        (cong₂ _+_ (sumTo-pick n (lo s) _ hl) (sumTo-pick n (hi s) _ hh))

-- The total action is kept: Σ_{k<n} F(k) = Σ A.
spread-total : ∀ n ss → All (Good n) ss → sumTo n (spread ss) ≡ totalAmt ss
spread-total n []       []                = sumTo-zero-fn n
spread-total n (s ∷ ss) ((hin , e) ∷ hs) =
  trans (sumTo-add n (deposit s) (spread ss))
        (cong₂ _+_ (trans (deposit-sum n s hin) (split-keeps (wlo s) (whi s) (amt s) e))
                   (spread-total n ss hs))

private
  mul-pick : ∀ (g : ℕ → ℚ) a c k → g k * pick a (λ _ → c) k ≡ pick a (λ j → g j * c) k
  mul-pick g a c k with k ℕ.≡ᵇ a
  ... | true  = refl
  ... | false = *-zeroʳ (g k)

-- The energy on the grid g: Σ_{k<n} g(k) F(k) = Σ A (wlo g(lo) + whi g(hi)).
spread-energy : ∀ n (g : ℕ → ℚ) ss → All (Inside n) ss →
  sumTo n (λ k → g k * spread ss k) ≡ energyAmt g ss
spread-energy n g []       []        = trans (sumTo-congr n _ _ (λ k _ → *-zeroʳ (g k)))
                                             (sumTo-zero-fn n)
spread-energy n g (s ∷ ss) (hin@(hl , hh) ∷ hs) =
  trans (sumTo-congr n _ (λ k → (P k + Q k) + g k * spread ss k) pt)
  (trans (sumTo-add n (λ k → P k + Q k) (λ k → g k * spread ss k))
  (cong₂ _+_
    (trans (sumTo-add n P Q)
    (trans (cong₂ _+_ (sumTo-pick n (lo s) _ hl) (sumTo-pick n (hi s) _ hh))
           (solve 5 (λ gl gh p q A → gl :* (p :* A) :+ gh :* (q :* A) := A :* (p :* gl :+ q :* gh))
              refl (g (lo s)) (g (hi s)) (wlo s) (whi s) (amt s))))
    (spread-energy n g ss hs)))
  where
  P Q : ℕ → ℚ
  P = pick (lo s) (λ j → g j * (wlo s * amt s))
  Q = pick (hi s) (λ j → g j * (whi s * amt s))
  pt : ∀ k → k ℕ.< n → g k * spread (s ∷ ss) k ≡ (P k + Q k) + g k * spread ss k
  pt k _ =
    trans (*-distribˡ-+ (g k) (deposit s k) (spread ss k))
          (cong (_+ g k * spread ss k)
            (trans (*-distribˡ-+ (g k) (pick (lo s) (λ _ → wlo s * amt s) k)
                                       (pick (hi s) (λ _ → whi s * amt s) k))
                   (cong₂ _+_ (mul-pick g (lo s) _ k) (mul-pick g (hi s) _ k))))

-- The share of an off-grid point x between the grid values g(i) and g(i+1).
interpShare : (ℕ → ℚ) → ℕ → ℚ → ℚ → Share
interpShare g i x A =
  share i (suc i) (wa (g i) (g (suc i)) x) (wb (g i) (g (suc i)) x) A

-- Its weights add to 1.
interpShare-good : ∀ g i x A → g i < g (suc i) →
  wlo (interpShare g i x A) + whi (interpShare g i x A) ≡ 1ℚ
interpShare-good g i x A h = weights-sum x h

-- Its energy term is A x.
share-energy : ∀ g i x A → g i < g (suc i) →
  amt (interpShare g i x A) * (wlo (interpShare g i x A) * g i
                               + whi (interpShare g i x A) * g (suc i)) ≡ A * x
share-energy g i x A h = cong (A *_) (interp-freq x h)

-- ---------------------------------------------------------------------------------------------
-- Bilinear weights: frequency between af < bf, direction between at < bt

record Bilinear : Set where
  constructor bilinear
  field
    w00 w01 w10 w11 : ℚ
open Bilinear public

bil : (af bf x at bt y : ℚ) → Bilinear
bil af bf x at bt y =
  bilinear (wa af bf x * wa at bt y) (wa af bf x * wb at bt y)
           (wb af bf x * wa at bt y) (wb af bf x * wb at bt y)

-- The four weights add to 1.
bilinear-sum : ∀ {af bf at bt} x y → af < bf → at < bt →
  let w = bil af bf x at bt y in w00 w + w01 w + w10 w + w11 w ≡ 1ℚ
bilinear-sum {af} {bf} {at} {bt} x y hf ht =
  trans (solve 4 (λ p q r s → p :* r :+ p :* s :+ q :* r :+ q :* s := (p :+ q) :* (r :+ s))
           refl (wa af bf x) (wb af bf x) (wa at bt y) (wb at bt y))
        (trans (cong₂ _*_ (weights-sum x hf) (weights-sum y ht)) refl)

-- The four weights are not negative inside the cell.
bilinear-nonneg : ∀ {af bf x at bt y} → af ≤ x → x ≤ bf → at ≤ y → y ≤ bt →
  let w = bil af bf x at bt y in
  0ℚ ≤ w00 w × 0ℚ ≤ w01 w × 0ℚ ≤ w10 w × 0ℚ ≤ w11 w
bilinear-nonneg hx1 hx2 hy1 hy2 =
  *-nonneg pa ra , *-nonneg pa rb , *-nonneg pb ra , *-nonneg pb rb
  where
  pa = wa-nonneg hx1 hx2
  pb = wb-nonneg hx1 hx2
  ra = wa-nonneg hy1 hy2
  rb = wb-nonneg hy1 hy2

-- The weights give back the frequency.
bilinear-freq : ∀ {af bf at bt} x y → af < bf → at < bt →
  let w = bil af bf x at bt y in (w00 w + w01 w) * af + (w10 w + w11 w) * bf ≡ x
bilinear-freq {af} {bf} {at} {bt} x y hf ht =
  trans (solve 6 (λ p q r s a b →
           (p :* r :+ p :* s) :* a :+ (q :* r :+ q :* s) :* b := (r :+ s) :* (p :* a :+ q :* b))
           refl (wa af bf x) (wb af bf x) (wa at bt y) (wb at bt y) af bf)
        (trans (cong₂ _*_ (weights-sum y ht) (interp-freq x hf)) (*-identityˡ x))

-- The weights give back the direction.
bilinear-dir : ∀ {af bf at bt} x y → af < bf → at < bt →
  let w = bil af bf x at bt y in (w00 w + w10 w) * at + (w01 w + w11 w) * bt ≡ y
bilinear-dir {af} {bf} {at} {bt} x y hf ht =
  trans (solve 6 (λ p q r s a b →
           (p :* r :+ q :* r) :* a :+ (p :* s :+ q :* s) :* b := (p :+ q) :* (r :* a :+ s :* b))
           refl (wa af bf x) (wb af bf x) (wa at bt y) (wb at bt y) at bt)
        (trans (cong₂ _*_ (weights-sum x hf) (interp-freq y ht)) (*-identityˡ y))

-- ---------------------------------------------------------------------------------------------
-- Examples: a grid with XFR = 11/10 from σ₀ = 1, and λ = 1/4

private
  xfr : ℚ
  xfr = ℤ+ 11 / 10

  σ : ℕ → ℚ
  σ ℕ.zero    = 1ℚ
  σ (suc i)   = σ i * xfr

  lam : ℚ
  lam = ℤ+ 1 / 4

  -- σ(1 + λ) for σ = σ(0) = 1 is 5/4. It lies between σ(2) = 1.21 and σ(3) = 1.331.
  up : ℚ
  up = σ 0 * (1ℚ + lam)

up-bracket : σ 2 < up × up < σ 3
up-bracket = from-yes (σ 2 <? up) , from-yes (up <? σ 3)

up-wa : wa (σ 2) (σ 3) up ≡ ℤ+ 81 / 121
up-wa = refl

up-wb : wb (σ 2) (σ 3) up ≡ ℤ+ 40 / 121
up-wb = refl

-- σ(1 - λ) for σ = σ(4) = 1.4641 is 1.098075. It lies between σ(0) = 1 and σ(1) = 1.1.
private
  down : ℚ
  down = σ 4 * (1ℚ - lam)

down-weights : wa (σ 0) (σ 1) down ≡ ℤ+ 77 / 4000 × wb (σ 0) (σ 1) down ≡ ℤ+ 3923 / 4000
down-weights = refl , refl

-- An action of 2 at 5/4 and an action of 1 at 1.098075. Bin 2 gets 162/121 and bin 3 gets
-- 80/121. On a grid of five bins the total is 3 and the energy is 2 · 5/4 + 1 · 1.098075.
private
  quartet : List Share
  quartet = interpShare σ 2 up (lit 2) ∷ interpShare σ 0 down 1ℚ ∷ []

example-bin2 : spread quartet 2 ≡ ℤ+ 162 / 121
example-bin2 = refl

example-total : sumTo 5 (spread quartet) ≡ lit 3
example-total = refl

example-energy : sumTo 5 (λ k → σ k * spread quartet k) ≡ lit 2 * up + 1ℚ * down
example-energy = refl

-- The quadratic over-estimate at 5/4 is strict: x² < wa a² + wb b².
example-convex : up * up < wa (σ 2) (σ 3) up * (σ 2 * σ 2) + wb (σ 2) (σ 3) up * (σ 3 * σ 3)
example-convex = from-yes (up * up <? wa (σ 2) (σ 3) up * (σ 2 * σ 2) + wb (σ 2) (σ 3) up * (σ 3 * σ 3))
