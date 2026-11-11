{-# OPTIONS --safe --without-K #-}

-- Finite sums over exact rationals, and tabulation, for the ocean-wave kernels. Ported from the
-- "Finite sums" and "Tabulation" parts of `ocean-waves/lean/OceanWaves/RatLemmas.lean`. The
-- order lemmas are in `Order.agda`.
module OceanWaves.Sums where

open import Data.Bool using (Bool; true; false; if_then_else_; T)
open import Data.Unit using (tt)
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc)
import Data.Nat.Properties as ℕP
open import Relation.Nullary using (does; yes; no; contradiction)
open import Data.Rational using (ℚ; 0ℚ; _+_; _-_; _*_; -_; _≤_)
open import Data.Rational.Properties
  using (nonNegative⁻¹; nonNeg*nonNeg⇒nonNeg; +-monoˡ-≤; +-inverseʳ; ≤-reflexive; ≤-trans;
         ≤-refl; +-mono-≤; +-identityˡ; +-identityʳ)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst)

-- `sumTo n f` is f 0 + f 1 + ... + f (n - 1).
sumTo : ℕ → (ℕ → ℚ) → ℚ
sumTo zero    f = 0ℚ
sumTo (suc n) f = sumTo n f + f n

-- A telescoping sum keeps only its two ends.
sumTo-telescope : ∀ n (f : ℕ → ℚ) → sumTo n (λ i → f i - f (suc i)) ≡ f 0 - f n
sumTo-telescope zero    f = sym (+-inverseʳ (f 0))
sumTo-telescope (suc n) f
  rewrite sumTo-telescope n f =
    solve 3 (λ a b c → (a :- b) :+ (b :- c) := a :- c) refl (f 0) (f n) (f (suc n))

-- The product of two non-negative rationals is non-negative.
*-nonneg : ∀ {p q} → 0ℚ ≤ p → 0ℚ ≤ q → 0ℚ ≤ p * q
*-nonneg {p} {q} hp hq =
  nonNegative⁻¹ (p * q) {{nonNeg*nonNeg⇒nonNeg p {{nonNegative hp}} q {{nonNegative hq}}}}

-- p ≤ q gives 0 ≤ q - p.
≤⇒0≤- : ∀ {p q} → p ≤ q → 0ℚ ≤ q - p
≤⇒0≤- {p} {q} h = ≤-trans (≤-reflexive (sym (+-inverseʳ p))) (+-monoˡ-≤ (- p) h)

-- ---------------------------------------------------------------------------------------------
-- More sums, for the source terms and the model step (the rest of `RatLemmas.lean`).

sumTo-add : ∀ n (f g : ℕ → ℚ) → sumTo n (λ i → f i + g i) ≡ sumTo n f + sumTo n g
sumTo-add zero    f g = refl
sumTo-add (suc n) f g rewrite sumTo-add n f g =
  solve 4 (λ a b x y → (a :+ b) :+ (x :+ y) := (a :+ x) :+ (b :+ y)) refl
    (sumTo n f) (sumTo n g) (f n) (g n)

sumTo-sub : ∀ n (f g : ℕ → ℚ) → sumTo n (λ i → f i - g i) ≡ sumTo n f - sumTo n g
sumTo-sub zero    f g = refl
sumTo-sub (suc n) f g rewrite sumTo-sub n f g =
  solve 4 (λ a b x y → (a :- b) :+ (x :- y) := (a :+ x) :- (b :+ y)) refl
    (sumTo n f) (sumTo n g) (f n) (g n)

sumTo-mul-left : ∀ n c (f : ℕ → ℚ) → sumTo n (λ i → c * f i) ≡ c * sumTo n f
sumTo-mul-left zero    c f = solve 1 (λ x → con 0ℚ := x :* con 0ℚ) refl c
sumTo-mul-left (suc n) c f rewrite sumTo-mul-left n c f =
  solve 3 (λ x s y → x :* s :+ x :* y := x :* (s :+ y)) refl c (sumTo n f) (f n)

sumTo-zero-fn : ∀ n → sumTo n (λ _ → 0ℚ) ≡ 0ℚ
sumTo-zero-fn zero    = refl
sumTo-zero-fn (suc n) rewrite sumTo-zero-fn n = refl

-- Sums look only at the indices below n.
sumTo-congr : ∀ n (f g : ℕ → ℚ) → (∀ i → i ℕ.< n → f i ≡ g i) → sumTo n f ≡ sumTo n g
sumTo-congr zero    f g h = refl
sumTo-congr (suc n) f g h =
  cong₂ _+_ (sumTo-congr n f g (λ i i<n → h i (ℕP.m<n⇒m<1+n i<n))) (h n (ℕP.n<1+n n))

-- Peel off the first term.
sumTo-succ-left : ∀ n (f : ℕ → ℚ) → sumTo (suc n) f ≡ f 0 + sumTo n (λ i → f (suc i))
sumTo-succ-left zero    f = solve 1 (λ x → con 0ℚ :+ x := x :+ con 0ℚ) refl (f 0)
sumTo-succ-left (suc n) f rewrite sumTo-succ-left n f =
  solve 3 (λ a s b → (a :+ s) :+ b := a :+ (s :+ b)) refl (f 0) (sumTo n (λ i → f (suc i))) (f (suc n))

sumTo-nonneg : ∀ n (f : ℕ → ℚ) → (∀ i → i ℕ.< n → 0ℚ ≤ f i) → 0ℚ ≤ sumTo n f
sumTo-nonneg zero    f h = ≤-refl
sumTo-nonneg (suc n) f h =
  +-mono-≤ (sumTo-nonneg n f (λ i i<n → h i (ℕP.m<n⇒m<1+n i<n))) (h n (ℕP.n<1+n n))

-- Equality of naturals as a Boolean, and what each answer says.
eqb-true : ∀ {m n} → (m ℕ.≡ᵇ n) ≡ true → m ≡ n
eqb-true {m} {n} e = ℕP.≡ᵇ⇒≡ m n (subst T (sym e) tt)

eqb-false : ∀ {m n} → (m ℕ.≡ᵇ n) ≡ false → m ≢ n
eqb-false {m} {n} e m≡n = subst T e (ℕP.≡⇒≡ᵇ m n m≡n)

-- The value of w at a, else zero: an indicator.
pick : ℕ → (ℕ → ℚ) → ℕ → ℚ
pick a w j = if j ℕ.≡ᵇ a then w j else 0ℚ

-- A sum of an indicator picks out one value.
sumTo-pick : ∀ n a (w : ℕ → ℚ) → a ℕ.< n → sumTo n (pick a w) ≡ w a
sumTo-pick zero    a w ()
sumTo-pick (suc n) a w a<n with n ℕ.≡ᵇ a in eq
... | true with eqb-true {n} {a} eq
...   | refl =
  trans (cong (_+ w n) (trans (sumTo-congr n (pick n w) (λ _ → 0ℚ) below) (sumTo-zero-fn n)))
        (+-identityˡ (w n))
  where
  below : ∀ j → j ℕ.< n → pick n w j ≡ 0ℚ
  below j j<n with j ℕ.≡ᵇ n in e
  ... | true  = contradiction (eqb-true e) (ℕP.<⇒≢ j<n)
  ... | false = refl
sumTo-pick (suc n) a w a<n | false =
  trans (+-identityʳ (sumTo n (pick a w)))
        (sumTo-pick n a w (ℕP.≤∧≢⇒< (ℕ.s≤s⁻¹ a<n) (λ a≡n → eqb-false eq (sym a≡n))))

-- Swap the order of a finite double sum.
sumTo-comm : ∀ m n (f : ℕ → ℕ → ℚ) →
  sumTo m (λ i → sumTo n (λ j → f i j)) ≡ sumTo n (λ j → sumTo m (λ i → f i j))
sumTo-comm zero    n f = sym (sumTo-zero-fn n)
sumTo-comm (suc m) n f rewrite sumTo-comm m n f =
  sym (sumTo-add n (λ j → sumTo m (λ i → f i j)) (λ j → f m j))

-- ---------------------------------------------------------------------------------------------
-- Tabulation. A field `ℕ → ℚ` is a function, so a composed kernel computes every value again
-- on every lookup. `tabulate` stores the first n values in a list once. The fast kernels use
-- it; the theorems show that they agree with the plain ones.

private
  table : ∀ {A : Set} → ℕ → (ℕ → A) → List A
  table zero    f = []
  table (suc n) f = f 0 ∷ table n (λ i → f (suc i))

  getD : ∀ {A : Set} → A → List A → ℕ → A
  getD d []       _       = d
  getD d (x ∷ xs) zero    = x
  getD d (x ∷ xs) (suc i) = getD d xs i

  getD-table : ∀ {A : Set} (d : A) n (f : ℕ → A) i → i ℕ.< n → getD d (table n f) i ≡ f i
  getD-table d (suc n) f zero    _   = refl
  getD-table d (suc n) f (suc i) i<n = getD-table d n (λ k → f (suc k)) i (ℕ.s≤s⁻¹ i<n)

-- The first n values of a field, as a list (Lean's `toList`).
toList : ℕ → (ℕ → ℚ) → List ℚ
toList = table

tabulate : ℕ → (ℕ → ℚ) → ℕ → ℚ
tabulate n f = getD 0ℚ (table n f)

tabulate-eq : ∀ n (f : ℕ → ℚ) i → i ℕ.< n → tabulate n f i ≡ f i
tabulate-eq n f = getD-table 0ℚ n f

-- A 2-D field: rows x < m, columns j < n.
tabulate2 : ℕ → ℕ → (ℕ → ℕ → ℚ) → ℕ → ℕ → ℚ
tabulate2 m n f = getD (λ _ → 0ℚ) (table m (λ x → tabulate n (f x)))

tabulate2-eq : ∀ m n (f : ℕ → ℕ → ℚ) x j → x ℕ.< m → j ℕ.< n → tabulate2 m n f x j ≡ f x j
tabulate2-eq m n f x j hx hj =
  trans (cong (λ row → row j) (getD-table (λ _ → 0ℚ) m (λ x → tabulate n (f x)) x hx))
        (tabulate-eq n (f x) j hj)
