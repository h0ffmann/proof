{-# OPTIONS --safe --without-K #-}

-- Solving the dispersion relation by bisection. Ported from
-- `ocean-waves/lean/OceanWaves/Bisection.lean`. The names follow Lean, with `-` for `_`.
--
-- WAVEWATCH III needs k for each discrete frequency σ and each depth h. `bisect f target n lo
-- hi` halves the bracket [lo, hi] n times, in exact arithmetic. The proofs need no continuity.
-- They show:
--
-- * the bracket invariant f lo < target ≤ f hi is kept (one side at a time);
-- * lo < hi is kept, and the width after n steps is (hi - lo) / 2ⁿ;
-- * if f is strictly increasing, every exact root is in (lo, hi].
--
-- The solver returns the upper end hi. So σ² ≤ σ²(hi) always holds, the phase speed from it
-- obeys c² ≤ g h (`phaseSpeed-sq-le`), and the time step of `courant-le-one` is safe, with no
-- claim that the root was found exactly.
--
-- Lean writes the step with `if f m < target then … else …`. Agda passes the answer to
-- `f m <? target` to `bisect-step`, and the proofs match on it.
module OceanWaves.Bisection where

open import Data.Nat using (ℕ; zero; suc)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; _≤_; _<_; _≟_; _<?_; _≤?_; _⊔_)
open import Data.Rational.Base using (nonNegative; positive)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; <-≤-trans; ≤-<-trans; <-trans; <⇒≤; ≤-reflexive; ≮⇒≥; <-irrefl;
         *-monoʳ-≤-nonNeg; *-monoˡ-≤-nonNeg; *-monoˡ-<-pos; *-identityʳ; p≤p⊔q; p≤q⊔p)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; :-_; con)
open import Relation.Nullary using (Dec; yes; no; contradiction)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; subst; subst₂)

open import OceanWaves.Order
open import OceanWaves.Dispersion

-- The midpoint of a bracket.
mid : ℚ → ℚ → ℚ
mid lo hi = (lo + hi) /₀ 2ℚ

mutual
  bisect : (ℚ → ℚ) → ℚ → ℕ → ℚ → ℚ → ℚ × ℚ
  bisect f target zero    lo hi = lo , hi
  bisect f target (suc n) lo hi = bisect-step f target n lo hi (f (mid lo hi) <? target)

  bisect-step : ∀ (f : ℚ → ℚ) target → ℕ → (lo hi : ℚ) → Dec (f (mid lo hi) < target) → ℚ × ℚ
  bisect-step f target n lo hi (yes _) = bisect f target n (mid lo hi) hi
  bisect-step f target n lo hi (no  _) = bisect f target n lo (mid lo hi)

private
  i2 = inv₀ 2ℚ

  2i : 2ℚ * i2 ≡ 1ℚ
  2i = inv₀-inverse 2ℚ (<⇒≢0 0<2)

  -- An equality that holds once 2 * (1/2) is replaced by 1.
  elim2 : ∀ {x y} c → x ≡ y + c * (2ℚ * i2) - c → x ≡ y
  elim2 {x} {y} c eq = trans eq (trans (cong (λ u → y + c * u - c) 2i)
                                       (solve 2 (λ y c → y :+ c :* con 1ℚ :- c := y) refl y c))

mid-between : ∀ {lo hi} → lo < hi → lo < mid lo hi × mid lo hi < hi
mid-between {lo} {hi} h =
  by-diff< e (elim2 lo (solve 3 (λ l h i → (l :+ h) :* i :- l
                               := (h :- l) :* i :+ l :* ((con 1ℚ :+ con 1ℚ) :* i) :- l) refl lo hi i2)) pos ,
  by-diff< e (elim2 (- hi) (solve 3 (λ l h i → h :- (l :+ h) :* i
                               := (h :- l) :* i :+ (:- h) :* ((con 1ℚ :+ con 1ℚ) :* i) :- (:- h)) refl lo hi i2)) pos
  where
  e   = (hi - lo) * i2
  pos = *-pos (<⇒0<- h) (inv₀-pos 0<2)

-- 2ⁿ, as Lean's `2 ^ n` with `pow_succ`: 2^(n+1) = 2^n * 2.
pow2 : ℕ → ℚ
pow2 zero    = 1ℚ
pow2 (suc n) = pow2 n * 2ℚ

module _ (f : ℚ → ℚ) (target : ℚ) where

  bisect-hi : ∀ n lo hi → target ≤ f hi → target ≤ f (proj₂ (bisect f target n lo hi))
  bisect-hi zero    lo hi h = h
  bisect-hi (suc n) lo hi h = go (f (mid lo hi) <? target)
    where
    go : ∀ d → target ≤ f (proj₂ (bisect-step f target n lo hi d))
    go (yes _)  = bisect-hi n (mid lo hi) hi h
    go (no  ¬p) = bisect-hi n lo (mid lo hi) (≮⇒≥ ¬p)

  bisect-lo : ∀ n lo hi → f lo < target → f (proj₁ (bisect f target n lo hi)) < target
  bisect-lo zero    lo hi h = h
  bisect-lo (suc n) lo hi h = go (f (mid lo hi) <? target)
    where
    go : ∀ d → f (proj₁ (bisect-step f target n lo hi d)) < target
    go (yes p) = bisect-lo n (mid lo hi) hi p
    go (no  _) = bisect-lo n lo (mid lo hi) h

  bisect-lt : ∀ n lo hi → lo < hi → proj₁ (bisect f target n lo hi) < proj₂ (bisect f target n lo hi)
  bisect-lt zero    lo hi h = h
  bisect-lt (suc n) lo hi h = go (f (mid lo hi) <? target)
    where
    go : ∀ d → proj₁ (bisect-step f target n lo hi d) < proj₂ (bisect-step f target n lo hi d)
    go (yes _) = bisect-lt n (mid lo hi) hi (proj₂ (mid-between h))
    go (no  _) = bisect-lt n lo (mid lo hi) (proj₁ (mid-between h))

  bisect-lo-mono : ∀ n lo hi → lo < hi → lo ≤ proj₁ (bisect f target n lo hi)
  bisect-lo-mono zero    lo hi h = ≤-refl
  bisect-lo-mono (suc n) lo hi h = go (f (mid lo hi) <? target)
    where
    go : ∀ d → lo ≤ proj₁ (bisect-step f target n lo hi d)
    go (yes _) = ≤-trans (<⇒≤ (proj₁ (mid-between h))) (bisect-lo-mono n (mid lo hi) hi (proj₂ (mid-between h)))
    go (no  _) = bisect-lo-mono n lo (mid lo hi) (proj₁ (mid-between h))

  -- The width halves at each step: (hi_n - lo_n) 2ⁿ = hi - lo.
  bisect-width : ∀ n lo hi →
    (proj₂ (bisect f target n lo hi) - proj₁ (bisect f target n lo hi)) * pow2 n ≡ hi - lo
  bisect-width zero    lo hi = *-identityʳ (hi - lo)
  bisect-width (suc n) lo hi = go (f (mid lo hi) <? target)
    where
    go : ∀ d → (proj₂ (bisect-step f target n lo hi d) - proj₁ (bisect-step f target n lo hi d)) * (pow2 n * 2ℚ)
               ≡ hi - lo
    go (yes _) = let b = bisect f target n (mid lo hi) hi in
      trans (solve 3 (λ x y p → (x :- y) :* (p :* (con 1ℚ :+ con 1ℚ)) := ((x :- y) :* p) :* (con 1ℚ :+ con 1ℚ))
               refl (proj₂ b) (proj₁ b) (pow2 n))
        (trans (cong (_* 2ℚ) (bisect-width n (mid lo hi) hi))
          (elim2 (- (lo + hi)) (solve 3 (λ l h i → (h :- (l :+ h) :* i) :* (con 1ℚ :+ con 1ℚ)
                   := (h :- l) :+ (:- (l :+ h)) :* ((con 1ℚ :+ con 1ℚ) :* i) :- (:- (l :+ h))) refl lo hi i2)))
    go (no  _) = let b = bisect f target n lo (mid lo hi) in
      trans (solve 3 (λ x y p → (x :- y) :* (p :* (con 1ℚ :+ con 1ℚ)) := ((x :- y) :* p) :* (con 1ℚ :+ con 1ℚ))
               refl (proj₂ b) (proj₁ b) (pow2 n))
        (trans (cong (_* 2ℚ) (bisect-width n lo (mid lo hi)))
          (elim2 (lo + hi) (solve 3 (λ l h i → ((l :+ h) :* i :- l) :* (con 1ℚ :+ con 1ℚ)
                   := (h :- l) :+ (l :+ h) :* ((con 1ℚ :+ con 1ℚ) :* i) :- (l :+ h)) refl lo hi i2)))

  -- Any root sits in the final bracket when f is strictly increasing on [lo, ∞).
  bisect-root : ∀ n lo hi r → (∀ a b → lo ≤ a → a < b → f a < f b) → lo < hi →
    f lo < target → target ≤ f hi → lo ≤ r → f r ≡ target →
    proj₁ (bisect f target n lo hi) < r × r ≤ proj₂ (bisect f target n lo hi)
  bisect-root n lo hi r hmono hlohi hlo hhi hr0 hr = first , second
    where
    b₁ = proj₁ (bisect f target n lo hi)
    b₂ = proj₂ (bisect f target n lo hi)
    h1 = bisect-lo n lo hi hlo
    h2 = bisect-hi n lo hi hhi
    h3 = bisect-lt n lo hi hlohi
    h4 = bisect-lo-mono n lo hi hlohi
    first : b₁ < r
    first with b₁ <? r
    ... | yes p = p
    ... | no  ¬p with r ≟ b₁
    ...   | yes refl = contradiction (subst (_< target) hr h1) (<-irrefl refl)
    ...   | no  r≢b₁ = contradiction (subst (_< target) hr (<-trans (hmono r b₁ hr0 r<b₁) h1)) (<-irrefl refl)
      where r<b₁ = ≤∧≢⇒< (≮⇒≥ ¬p) r≢b₁
    second : r ≤ b₂
    second with r ≤? b₂
    ... | yes p = p
    ... | no  ¬p = contradiction (≤-<-trans h2 (subst (f b₂ <_) hr (hmono b₂ r (≤-trans h4 (<⇒≤ h3)) (≰⇒>′ ¬p))))
                                 (<-irrefl refl)
      where open import Data.Rational.Properties using () renaming (≰⇒> to ≰⇒>′)

two-pow-pos : ∀ n → 0ℚ < pow2 n
two-pow-pos zero    = 0<1
two-pow-pos (suc n) = *-pos (two-pow-pos n) 0<2

sq-pos-of-ne : ∀ {σ} → σ ≢ 0ℚ → 0ℚ < σ * σ
sq-pos-of-ne {σ} ne with σ <? 0ℚ
... | yes σ<0 = subst (0ℚ <_) (solve 1 (λ s → (:- s) :* (:- s) := s :* s) refl σ)
                  (*-pos (neg-pos σ<0) (neg-pos σ<0))
  where
  neg-pos : ∀ {x} → x < 0ℚ → 0ℚ < - x
  neg-pos {x} h = subst (0ℚ <_) (solve 1 (λ y → con 0ℚ :- y := :- y) refl x) (<⇒0<- h)
... | no  σ≮0 = *-pos p p
  where p = ≤∧≢⇒< (≮⇒≥ σ≮0) (λ eq → ne (sym eq))

-- ---------------------------------------------------------------------------------------------
-- The dispersion solver

module _ (M : TanhModel) (W : Medium) where
  open TanhModel M using (sat; sat-pos)
  open Medium W

  -- The starting upper bracket: max (σ²/g) (sat/h). Then k h ≥ sat, so the model is in its
  -- deep regime and σ²(k) = g k ≥ σ².
  kHi0 : ℚ → ℚ
  kHi0 σ = (σ * σ /₀ g) ⊔ (sat /₀ h)

  kHi0-pos : ∀ σ → 0ℚ < kHi0 σ
  kHi0-pos σ = <-≤-trans (div-pos sat-pos h-pos) (p≤q⊔p (σ * σ /₀ g) (sat /₀ h))

  kHi0-bracket : ∀ σ → σ * σ ≤ sigma2 M W (kHi0 σ)
  kHi0-bracket σ =
    ≤-trans (≤-trans (≤-reflexive (sym (mul-div-cancel (σ * σ) (<⇒≢0 g-pos))))
                     (*-monoˡ-≤-nonNeg g {{nonNegative (<⇒≤ g-pos)}} (p≤p⊔q (σ * σ /₀ g) (sat /₀ h))))
            (≤-reflexive (sym (sigma2-deep-exact M W hs)))
    where
    hs : sat ≤ kHi0 σ * h
    hs = ≤-trans (≤-reflexive (sym (div-mul-cancel sat (<⇒≢0 h-pos))))
                 (*-monoʳ-≤-nonNeg h {{nonNegative (<⇒≤ h-pos)}} (p≤q⊔p (σ * σ /₀ g) (sat /₀ h)))

  -- The bracket after `iters` halvings of [0, kHi0].
  kBracket : ℚ → ℕ → ℚ × ℚ
  kBracket σ iters = bisect (sigma2 M W) (σ * σ) iters 0ℚ (kHi0 σ)

  -- The wavenumber kernel: the upper end of the final bracket.
  waveNumber : ℚ → ℕ → ℚ
  waveNumber σ iters = proj₂ (kBracket σ iters)

  waveNumber-pos : ∀ σ iters → 0ℚ < waveNumber σ iters
  waveNumber-pos σ iters =
    ≤-<-trans (bisect-lo-mono (sigma2 M W) (σ * σ) iters 0ℚ _ (kHi0-pos σ))
              (bisect-lt (sigma2 M W) (σ * σ) iters 0ℚ _ (kHi0-pos σ))

  -- The returned k is never below the root: σ² ≤ σ²(k).
  waveNumber-upper : ∀ σ iters → σ * σ ≤ sigma2 M W (waveNumber σ iters)
  waveNumber-upper σ iters = bisect-hi (sigma2 M W) (σ * σ) iters 0ℚ _ (kHi0-bracket σ)

  -- The error bound: if σ ≠ 0 and r is a root, then 0 ≤ k - r < kHi0 / 2ⁿ.
  waveNumber-error : ∀ σ → σ ≢ 0ℚ → ∀ iters r → 0ℚ ≤ r → sigma2 M W r ≡ σ * σ →
    r ≤ waveNumber σ iters × (waveNumber σ iters - r) * pow2 iters < kHi0 σ
  waveNumber-error σ hσ iters r hr0 hr = proj₂ hroot , err
    where
    f = sigma2 M W
    t = σ * σ
    b = bisect f t iters 0ℚ (kHi0 σ)
    h0 : f 0ℚ ≡ 0ℚ
    h0 = solve 2 (λ g a → g :* con 0ℚ :* a := con 0ℚ) refl g (TanhModel.T M (0ℚ * h))
    hroot = bisect-root f t iters 0ℚ (kHi0 σ) r (λ a b ha hab → sigma2-strictMono M W ha hab)
              (kHi0-pos σ) (subst (_< t) (sym h0) (sq-pos-of-ne hσ)) (kHi0-bracket σ) hr0 hr
    P = pow2 iters
    err : (proj₂ b - r) * P < kHi0 σ
    err = <-≤-trans
      (*-monoˡ-<-pos P {{positive (two-pow-pos iters)}}
         (by-diff< {a = proj₂ b - r} {b = proj₂ b - proj₁ b} (r - proj₁ b) (solve 3 (λ x y z → (x :- z) :- (x :- y) := y :- z) refl (proj₂ b) r (proj₁ b))
                   (<⇒0<- (proj₁ hroot))))
      (≤-reflexive (trans (bisect-width f t iters 0ℚ (kHi0 σ))
                          (solve 1 (λ x → x :- con 0ℚ := x) refl (kHi0 σ))))
