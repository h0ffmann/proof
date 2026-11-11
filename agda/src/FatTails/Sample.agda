{-# OPTIONS --safe --without-K #-}

-- A finite sample of exact rationals: its size, sums over it, its mean, its largest value, and
-- the lemmas that the fat-tail metrics use. `fat-tails/python/fat_tails.py` takes the same means
-- with NumPy (`np.mean`, `.sum()`, `np.maximum.accumulate`) over floating-point numbers. Here
-- every number is a rational, and every statement is exact.
--
-- The lemmas take a function `f` and a hypothesis for each point (`∀ x → f x ≡ c * g x`), not an
-- equality of functions: `--safe --without-K` has no function extensionality.
module FatTails.Sample where

open import Data.List using (List; []; _∷_; map; _++_; concat)
open import Data.Rational
  using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; _≤_; _<_; _⊔_; _≟_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; <-≤-trans; ≤-reflexive; +-mono-≤; *-zeroʳ; *-zeroˡ; *-identityʳ;
         *-identityˡ; p≤q⇒p⊔q≡q; p≥q⇒p⊔q≡p; ≤-total; ⊔-lub; p≤p⊔q; p≤q⊔p; <-irrefl;
         *-monoˡ-≤-nonNeg; _≤?_; _<?_)
open import Relation.Nullary.Decidable using (from-yes)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Data.Sum using (inj₁; inj₂)
open import Relation.Nullary using (Dec; yes; no; contradiction)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst)

open import OceanWaves.Order
  using (inv₀; _/₀_; inv₀-inverse; inv₀-nonneg; inv₀-pos; <⇒≢0; +-nonneg; +-pos; *-nonneg;
         ≤∧≢⇒<; le-div-of-mul-le; div-le-of-le-mul; by-diff; sq-nonneg)
  public

-- ---------------------------------------------------------------------------------------------
-- Size, sum, mean, maximum

-- The number of points, as a rational: 1 + 1 + ... + 1.
size : ∀ {A : Set} → List A → ℚ
size []       = 0ℚ
size (_ ∷ xs) = 1ℚ + size xs

-- `sumMap f xs` is f x₁ + f x₂ + ... + f xₙ.
sumMap : (ℚ → ℚ) → List ℚ → ℚ
sumMap f []       = 0ℚ
sumMap f (x ∷ xs) = f x + sumMap f xs

sum : List ℚ → ℚ
sum []       = 0ℚ
sum (x ∷ xs) = x + sum xs

-- The sample mean, Σ x / n. The mean of no points is 0 (Lean's total division).
mean : List ℚ → ℚ
mean xs = sum xs /₀ size xs

-- `maxMap f xs` is the largest f x, and 0 for no points. The metrics apply it to non-negative
-- values (|x|^p), where 0 is the right start.
maxMap : (ℚ → ℚ) → List ℚ → ℚ
maxMap f []       = 0ℚ
maxMap f (x ∷ xs) = f x ⊔ maxMap f xs

-- ---------------------------------------------------------------------------------------------
-- Size

size-nonneg : ∀ {A : Set} (xs : List A) → 0ℚ ≤ size xs
size-nonneg []       = ≤-refl
size-nonneg (_ ∷ xs) = +-nonneg (from-yes (0ℚ ≤? 1ℚ)) (size-nonneg xs)

size-cons-pos : ∀ {A : Set} (x : A) xs → 0ℚ < size (x ∷ xs)
size-cons-pos x xs = +-pos (from-yes (0ℚ <? 1ℚ)) (size-nonneg xs)

size-map : ∀ {A B : Set} (f : A → B) (xs : List A) → size (map f xs) ≡ size xs
size-map f []       = refl
size-map f (x ∷ xs) = cong (1ℚ +_) (size-map f xs)

size-++ : ∀ {A : Set} (xs ys : List A) → size (xs ++ ys) ≡ size xs + size ys
size-++ []       ys = solve 1 (λ y → y := con 0ℚ :+ y) refl (size ys)
size-++ (x ∷ xs) ys rewrite size-++ xs ys =
  solve 2 (λ a b → con 1ℚ :+ (a :+ b) := (con 1ℚ :+ a) :+ b) refl (size xs) (size ys)

-- ---------------------------------------------------------------------------------------------
-- Sums

sum-is-sumMap : ∀ xs → sum xs ≡ sumMap (λ x → x) xs
sum-is-sumMap []       = refl
sum-is-sumMap (x ∷ xs) = cong (x +_) (sum-is-sumMap xs)

sumMap-cong : ∀ (f g : ℚ → ℚ) xs → (∀ x → f x ≡ g x) → sumMap f xs ≡ sumMap g xs
sumMap-cong f g []       h = refl
sumMap-cong f g (x ∷ xs) h = cong₂ _+_ (h x) (sumMap-cong f g xs h)

sumMap-map : ∀ (f g : ℚ → ℚ) xs → sumMap f (map g xs) ≡ sumMap (λ x → f (g x)) xs
sumMap-map f g []       = refl
sumMap-map f g (x ∷ xs) = cong (f (g x) +_) (sumMap-map f g xs)

sumMap-scale : ∀ c (f : ℚ → ℚ) xs → sumMap (λ x → c * f x) xs ≡ c * sumMap f xs
sumMap-scale c f []       = sym (*-zeroʳ c)
sumMap-scale c f (x ∷ xs) rewrite sumMap-scale c f xs =
  solve 3 (λ k a s → k :* a :+ k :* s := k :* (a :+ s)) refl c (f x) (sumMap f xs)

sumMap-+ : ∀ (f g : ℚ → ℚ) xs → sumMap (λ x → f x + g x) xs ≡ sumMap f xs + sumMap g xs
sumMap-+ f g []       = refl
sumMap-+ f g (x ∷ xs) rewrite sumMap-+ f g xs =
  solve 4 (λ a b s t → (a :+ b) :+ (s :+ t) := (a :+ s) :+ (b :+ t)) refl
    (f x) (g x) (sumMap f xs) (sumMap g xs)

sumMap-const : ∀ c xs → sumMap (λ _ → c) xs ≡ c * size xs
sumMap-const c []       = sym (*-zeroʳ c)
sumMap-const c (x ∷ xs) rewrite sumMap-const c xs =
  solve 2 (λ k n → k :+ k :* n := k :* (con 1ℚ :+ n)) refl c (size xs)

sumMap-++ : ∀ (f : ℚ → ℚ) xs ys → sumMap f (xs ++ ys) ≡ sumMap f xs + sumMap f ys
sumMap-++ f []       ys = solve 1 (λ y → y := con 0ℚ :+ y) refl (sumMap f ys)
sumMap-++ f (x ∷ xs) ys rewrite sumMap-++ f xs ys =
  solve 3 (λ a s t → a :+ (s :+ t) := (a :+ s) :+ t) refl (f x) (sumMap f xs) (sumMap f ys)

sumMap-nonneg : ∀ (f : ℚ → ℚ) xs → (∀ x → 0ℚ ≤ f x) → 0ℚ ≤ sumMap f xs
sumMap-nonneg f []       h = ≤-refl
sumMap-nonneg f (x ∷ xs) h = +-nonneg (h x) (sumMap-nonneg f xs h)

sumMap-mono : ∀ (f g : ℚ → ℚ) xs → (∀ x → f x ≤ g x) → sumMap f xs ≤ sumMap g xs
sumMap-mono f g []       h = ≤-refl
sumMap-mono f g (x ∷ xs) h = +-mono-≤ (h x) (sumMap-mono f g xs h)

-- Σ (x - c) = Σ x - n c.
sumMap-centre : ∀ c xs → sumMap (λ x → x - c) xs ≡ sum xs - c * size xs
sumMap-centre c []       = solve 1 (λ k → con 0ℚ := con 0ℚ :- k :* con 0ℚ) refl c
sumMap-centre c (x ∷ xs) rewrite sumMap-centre c xs =
  solve 4 (λ k a s n → (a :- k) :+ (s :- k :* n) := (a :+ s) :- k :* (con 1ℚ :+ n)) refl
    c x (sum xs) (size xs)

-- ---------------------------------------------------------------------------------------------
-- Maximum

-- c (a ⊔ b) = c a ⊔ c b for c ≥ 0.
*-distrib-⊔ : ∀ {c} a b → 0ℚ ≤ c → c * (a ⊔ b) ≡ (c * a) ⊔ (c * b)
*-distrib-⊔ {c} a b hc with ≤-total a b
... | inj₁ a≤b = trans (cong (c *_) (p≤q⇒p⊔q≡q a≤b))
                       (sym (p≤q⇒p⊔q≡q (*-monoˡ-≤-nonNeg c {{nonNegative hc}} a≤b)))
... | inj₂ b≤a = trans (cong (c *_) (p≥q⇒p⊔q≡p b≤a))
                       (sym (p≥q⇒p⊔q≡p (*-monoˡ-≤-nonNeg c {{nonNegative hc}} b≤a)))

maxMap-cong : ∀ (f g : ℚ → ℚ) xs → (∀ x → f x ≡ g x) → maxMap f xs ≡ maxMap g xs
maxMap-cong f g []       h = refl
maxMap-cong f g (x ∷ xs) h = cong₂ _⊔_ (h x) (maxMap-cong f g xs h)

maxMap-map : ∀ (f g : ℚ → ℚ) xs → maxMap f (map g xs) ≡ maxMap (λ x → f (g x)) xs
maxMap-map f g []       = refl
maxMap-map f g (x ∷ xs) = cong (f (g x) ⊔_) (maxMap-map f g xs)

maxMap-scale : ∀ {c} (f : ℚ → ℚ) xs → 0ℚ ≤ c → maxMap (λ x → c * f x) xs ≡ c * maxMap f xs
maxMap-scale {c} f []       hc = sym (*-zeroʳ c)
maxMap-scale {c} f (x ∷ xs) hc =
  trans (cong ((c * f x) ⊔_) (maxMap-scale f xs hc)) (sym (*-distrib-⊔ (f x) (maxMap f xs) hc))

maxMap-nonneg : ∀ (f : ℚ → ℚ) xs → 0ℚ ≤ maxMap f xs
maxMap-nonneg f []       = ≤-refl
maxMap-nonneg f (x ∷ xs) = ≤-trans (maxMap-nonneg f xs) (p≤q⊔p (f x) (maxMap f xs))

-- Each value is at most the maximum.
le-maxMap : ∀ (f : ℚ → ℚ) x xs → f x ≤ maxMap f (x ∷ xs)
le-maxMap f x xs = p≤p⊔q (f x) (maxMap f xs)

-- For non-negative values, the maximum is at most the sum.
maxMap-le-sumMap : ∀ (f : ℚ → ℚ) xs → (∀ x → 0ℚ ≤ f x) → maxMap f xs ≤ sumMap f xs
maxMap-le-sumMap f []       h = ≤-refl
maxMap-le-sumMap f (x ∷ xs) h =
  ⊔-lub (≤-trans (≤-reflexive (sym (+-identityʳ′ (f x)))) (+-mono-≤ (≤-refl {f x}) (sumMap-nonneg f xs h)))
        (≤-trans (≤-reflexive (sym (+-identityˡ′ (maxMap f xs))))
                 (+-mono-≤ (h x) (maxMap-le-sumMap f xs h)))
  where
  open import Data.Rational.Properties using () renaming (+-identityʳ to +-identityʳ′; +-identityˡ to +-identityˡ′)

-- The sum is at most n times the maximum.
sumMap-le-size*maxMap : ∀ (f : ℚ → ℚ) xs → sumMap f xs ≤ size xs * maxMap f xs
sumMap-le-size*maxMap f []       = ≤-reflexive (sym (*-zeroˡ 0ℚ))
sumMap-le-size*maxMap f (x ∷ xs) =
  ≤-trans (+-mono-≤ (le-maxMap f x xs)
                    (≤-trans (sumMap-le-size*maxMap f xs)
                             (*-monoˡ-≤-nonNeg (size xs) {{nonNegative (size-nonneg xs)}}
                               (p≤q⊔p (f x) (maxMap f xs)))))
          (≤-reflexive (solve 2 (λ m n → m :+ n :* m := (con 1ℚ :+ n) :* m) refl
                          (maxMap f (x ∷ xs)) (size xs)))

-- ---------------------------------------------------------------------------------------------
-- Division

-- The inverse of a number is the only number that gives 1 with it.
inv₀-unique : ∀ {x y} → x * y ≡ 1ℚ → inv₀ x ≡ y
inv₀-unique {x} {y} h =
  trans (sym (*-identityʳ (inv₀ x)))
    (trans (cong (inv₀ x *_) (sym h))
      (trans (solve 3 (λ i a b → i :* (a :* b) := (a :* i) :* b) refl (inv₀ x) x y)
        (trans (cong (_* y) (inv₀-inverse x x≢0)) (*-identityˡ y))))
  where
  x≢0 : x ≢ 0ℚ
  x≢0 refl = contradiction (trans (sym h) (*-zeroˡ y)) (λ ())

*≢0 : ∀ {a b} → a ≢ 0ℚ → b ≢ 0ℚ → a * b ≢ 0ℚ
*≢0 {a} {b} ha hb ab≡0 = hb b≡0
  where
  b≡0 : b ≡ 0ℚ
  b≡0 = trans (sym (*-identityˡ b))
         (trans (cong (_* b) (sym (trans (solve 2 (λ i x → i :* x := x :* i) refl (inv₀ a) a) (inv₀-inverse a ha))))
           (trans (solve 3 (λ i x y → (i :* x) :* y := i :* (x :* y)) refl (inv₀ a) a b)
             (trans (cong (inv₀ a *_) ab≡0) (*-zeroʳ (inv₀ a)))))

inv₀-* : ∀ {a b} → a ≢ 0ℚ → b ≢ 0ℚ → inv₀ (a * b) ≡ inv₀ a * inv₀ b
inv₀-* {a} {b} ha hb = inv₀-unique {a * b} {inv₀ a * inv₀ b}
  (trans (solve 4 (λ x y i j → (x :* y) :* (i :* j) := (x :* i) :* (y :* j)) refl a b (inv₀ a) (inv₀ b))
    (trans (cong₂ _*_ (inv₀-inverse a ha) (inv₀-inverse b hb)) (*-identityˡ 1ℚ)))

-- A common non-zero factor cancels: (k a) / (k b) = a / b, for every b (b = 0 gives 0 = 0).
div-cancelˡ : ∀ {k} a b → k ≢ 0ℚ → (k * a) /₀ (k * b) ≡ a /₀ b
div-cancelˡ {k} a b hk = go (b ≟ 0ℚ)
  where
  go : Dec (b ≡ 0ℚ) → (k * a) /₀ (k * b) ≡ a /₀ b
  go (yes refl) = trans (cong (λ q → (k * a) * inv₀ q) (*-zeroʳ k))
                    (trans (*-zeroʳ (k * a)) (sym (*-zeroʳ a)))
  go (no b≢0) =
    trans (cong ((k * a) *_) (inv₀-* hk b≢0))
      (trans (solve 4 (λ x y i j → (x :* y) :* (i :* j) := (x :* i) :* (y :* j)) refl k a (inv₀ k) (inv₀ b))
        (trans (cong (_* (a * inv₀ b)) (inv₀-inverse k hk)) (*-identityˡ (a /₀ b))))

-- c a / b = c (a / b): a factor of the numerator comes out.
div-scaleˡ : ∀ c a b → (c * a) /₀ b ≡ c * (a /₀ b)
div-scaleˡ c a b = solve 3 (λ k x i → (k :* x) :* i := k :* (x :* i)) refl c a (inv₀ b)

sum-scale : ∀ c xs → sum (map (c *_) xs) ≡ c * sum xs
sum-scale c []       = sym (*-zeroʳ c)
sum-scale c (y ∷ ys) rewrite sum-scale c ys =
  solve 3 (λ k a s → k :* a :+ k :* s := k :* (a :+ s)) refl c y (sum ys)

sum-++ : ∀ xs ys → sum (xs ++ ys) ≡ sum xs + sum ys
sum-++ []       ys = solve 1 (λ y → y := con 0ℚ :+ y) refl (sum ys)
sum-++ (x ∷ xs) ys rewrite sum-++ xs ys =
  solve 3 (λ a s t → a :+ (s :+ t) := (a :+ s) :+ t) refl x (sum xs) (sum ys)

-- The mean of c x is c times the mean.
mean-scale : ∀ c xs → mean (map (c *_) xs) ≡ c * mean xs
mean-scale c xs =
  trans (cong₂ _/₀_ (sum-scale c xs) (size-map (c *_) xs)) (div-scaleˡ c (sum xs) (size xs))

-- The mean of x + a is the mean plus a, when there is at least one point.
mean-shift : ∀ a y ys → mean (map (_+ a) (y ∷ ys)) ≡ mean (y ∷ ys) + a
mean-shift a y ys =
  trans (cong₂ _/₀_ (sum-map-shift (y ∷ ys)) (size-map (_+ a) (y ∷ ys)))
    (trans (solve 4 (λ s k n i → (s :+ k :* n) :* i := s :* i :+ k :* (n :* i)) refl
              (sum (y ∷ ys)) a n (inv₀ n))
      (trans (cong (λ t → sum (y ∷ ys) /₀ n + a * t) (inv₀-inverse n (λ eq → <⇒≢0 (size-cons-pos y ys) eq)))
        (cong (mean (y ∷ ys) +_) (*-identityʳ a))))
  where
  n = size (y ∷ ys)
  sum-map-shift : ∀ zs → sum (map (_+ a) zs) ≡ sum zs + a * size zs
  sum-map-shift []       = solve 1 (λ k → con 0ℚ := con 0ℚ :+ k :* con 0ℚ) refl a
  sum-map-shift (z ∷ zs) rewrite sum-map-shift zs =
    solve 4 (λ k x s m → (x :+ k) :+ (s :+ k :* m) := (x :+ s) :+ k :* (con 1ℚ :+ m)) refl
      a z (sum zs) (size zs)

-- A mean of points that are all at least t is at least t.
sum-ge : ∀ t xs → All (t ≤_) xs → t * size xs ≤ sum xs
sum-ge t []       []         = ≤-reflexive (*-zeroʳ t)
sum-ge t (x ∷ xs) (h ∷ hs) =
  ≤-trans (≤-reflexive (solve 2 (λ k n → k :* (con 1ℚ :+ n) := k :+ k :* n) refl t (size xs)))
          (+-mono-≤ h (sum-ge t xs hs))

mean-ge : ∀ t y ys → All (t ≤_) (y ∷ ys) → t ≤ mean (y ∷ ys)
mean-ge t y ys h = le-div-of-mul-le (size-cons-pos y ys)
  (≤-trans (≤-reflexive (solve 2 (λ k n → k :* n := k :* n) refl t (size (y ∷ ys)))) (sum-ge t (y ∷ ys) h))
