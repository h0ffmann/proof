{-# OPTIONS --safe --without-K #-}

-- The prediction of a gradient-boosted tree ensemble (XGBoost in `tv-audience/python/experiment.py`):
-- a base score plus the sum of the trees' leaf values. A tree sends a row left when its feature j
-- is below the split threshold θ. The fitted trees come from training, which stays outside Agda:
-- here a tree is any tree, so every theorem holds for the 600 trees the experiment fits.
--
-- The theorems: a tree's value is between its smallest and its largest leaf, so the ensemble's
-- prediction is between the base plus the sum of the smallest leaves and the base plus the sum of
-- the largest; two rows on the same side of every split get the same prediction (the model is
-- piecewise constant); and the prediction of two ensembles joined is the sum of their parts.
--
-- XGBoost also sends a missing feature to a default side, which this tree does not model.
module TvAudience.Trees where

open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.List using (List; []; _∷_; _++_)
open import Data.Nat using (ℕ)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Unit using (⊤; tt)
open import Data.Rational
  using (ℚ; 0ℚ; _+_; _≤_; _⊓_; _⊔_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; +-mono-≤; p⊓q≤p; p⊓q≤q; p≤p⊔q; p≤q⊔p; _<?_)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; con)
open import Relation.Nullary using (does)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂)

data Tree : Set where
  leaf : ℚ → Tree
  node : ℕ → ℚ → Tree → Tree → Tree   -- feature j, threshold θ, below θ, at or above θ

Features : Set
Features = ℕ → ℚ

eval : Features → Tree → ℚ
eval x (leaf v)       = v
eval x (node j θ l r) = if does (x j <? θ) then eval x l else eval x r

treeSum : Features → List Tree → ℚ
treeSum x []       = 0ℚ
treeSum x (t ∷ ts) = eval x t + treeSum x ts

predict : ℚ → List Tree → Features → ℚ
predict base ts x = base + treeSum x ts

lo hi : Tree → ℚ
lo (leaf v)       = v
lo (node _ _ l r) = lo l ⊓ lo r
hi (leaf v)       = v
hi (node _ _ l r) = hi l ⊔ hi r

loSum hiSum : List Tree → ℚ
loSum []       = 0ℚ
loSum (t ∷ ts) = lo t + loSum ts
hiSum []       = 0ℚ
hiSum (t ∷ ts) = hi t + hiSum ts

-- ---------------------------------------------------------------------------------------------

private
  if-elim : ∀ {A : Set} (P : A → Set) b {a c} → P a → P c → P (if b then a else c)
  if-elim P true  pa pc = pa
  if-elim P false pa pc = pc

eval-between : ∀ x t → lo t ≤ eval x t × eval x t ≤ hi t
eval-between x (leaf v)       = ≤-refl , ≤-refl
eval-between x (node j θ l r) =
  if-elim (λ e → lo l ⊓ lo r ≤ e) (does (x j <? θ))
          (≤-trans (p⊓q≤p (lo l) (lo r)) (proj₁ (eval-between x l)))
          (≤-trans (p⊓q≤q (lo l) (lo r)) (proj₁ (eval-between x r)))
  , if-elim (λ e → e ≤ hi l ⊔ hi r) (does (x j <? θ))
          (≤-trans (proj₂ (eval-between x l)) (p≤p⊔q (hi l) (hi r)))
          (≤-trans (proj₂ (eval-between x r)) (p≤q⊔p (hi l) (hi r)))

predict-between : ∀ base ts x →
  base + loSum ts ≤ predict base ts x × predict base ts x ≤ base + hiSum ts
predict-between base ts x = +-mono-≤ (≤-refl {base}) (sums ts) , +-mono-≤ (≤-refl {base}) (sums′ ts)
  where
  sums : ∀ ts → loSum ts ≤ treeSum x ts
  sums []       = ≤-refl
  sums (t ∷ ts) = +-mono-≤ (proj₁ (eval-between x t)) (sums ts)
  sums′ : ∀ ts → treeSum x ts ≤ hiSum ts
  sums′ []       = ≤-refl
  sums′ (t ∷ ts) = +-mono-≤ (proj₂ (eval-between x t)) (sums′ ts)

-- Two rows on the same side of every split of a tree.
SameSide : Features → Features → Tree → Set
SameSide x y (leaf _)       = ⊤
SameSide x y (node j θ l r) = (does (x j <? θ) ≡ does (y j <? θ)) × SameSide x y l × SameSide x y r

eval-same : ∀ x y t → SameSide x y t → eval x t ≡ eval y t
eval-same x y (leaf v)       tt              = refl
eval-same x y (node j θ l r) (h , hl , hr) =
  trans (cong (λ b → if b then eval x l else eval x r) h)
        (cong₂ (λ p q → if does (y j <? θ) then p else q) (eval-same x y l hl) (eval-same x y r hr))

AllSameSide : Features → Features → List Tree → Set
AllSameSide x y []       = ⊤
AllSameSide x y (t ∷ ts) = SameSide x y t × AllSameSide x y ts

predict-same : ∀ base ts x y → AllSameSide x y ts → predict base ts x ≡ predict base ts y
predict-same base ts x y h = cong (base +_) (sums ts h)
  where
  sums : ∀ ts → AllSameSide x y ts → treeSum x ts ≡ treeSum y ts
  sums []       tt       = refl
  sums (t ∷ ts) (h , hs) = cong₂ _+_ (eval-same x y t h) (sums ts hs)

treeSum-++ : ∀ x ts us → treeSum x (ts ++ us) ≡ treeSum x ts + treeSum x us
treeSum-++ x []       us = solve 1 (λ s → s := con 0ℚ :+ s) refl (treeSum x us)
treeSum-++ x (t ∷ ts) us rewrite treeSum-++ x ts us =
  solve 3 (λ a s u → a :+ (s :+ u) := (a :+ s) :+ u) refl (eval x t) (treeSum x ts) (treeSum x us)

-- Boosting adds trees: the first rounds and the later rounds add up.
predict-++ : ∀ base ts us x → predict base (ts ++ us) x ≡ predict base ts x + treeSum x us
predict-++ base ts us x rewrite treeSum-++ x ts us =
  solve 3 (λ b s u → b :+ (s :+ u) := (b :+ s) :+ u) refl base (treeSum x ts) (treeSum x us)
