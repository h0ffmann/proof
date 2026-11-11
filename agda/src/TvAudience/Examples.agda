{-# OPTIONS --safe --without-K #-}

-- Every definition of TvAudience on small numbers, checked by `refl`: Agda computes the exact
-- rationals. `tools/tv-audience/` computes the same examples with its Haskell mirror and needs
-- each one to be equal.
module TvAudience.Examples where

open import Data.Bool using (true; false)
open import Data.Integer using (+_)
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; _%_)
open import Data.Product using (_,_)
open import Data.Rational as ℚ using (ℚ; 0ℚ; 1ℚ; _/_; -_; _⊔_)
open import Data.Rational.Properties using (_≤?_)
open import Relation.Nullary.Decidable using (from-yes)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import TvAudience.Wape
open import TvAudience.Baselines
open import TvAudience.Split
open import TvAudience.Panel
open import TvAudience.Jcs
open import TvAudience.Winner
open import TvAudience.Trees

-- Three channel-slots, in millions: (actual, forecast).
rows : List Row
rows = (+ 10 / 1 , + 8 / 1) ∷ (+ 4 / 1 , + 5 / 1) ∷ (+ 6 / 1 , + 6 / 1) ∷ []

wape-rows : wape rows ≡ + 3 / 20
wape-rows = refl

mae-rows : mae rows ≡ 1ℚ
mae-rows = refl

mse-rows : mse rows ≡ + 5 / 3
mse-rows = refl

-- In thousands of viewers.
wape-thousands : wape (scale (+ 1000 / 1) rows) ≡ + 3 / 20
wape-thousands = refl

-- The big show alone, the other slots alone, and the two pooled.
wape-big : wape ((+ 10 / 1 , + 8 / 1) ∷ []) ≡ + 1 / 5
wape-big = refl

wape-rest : wape ((+ 4 / 1 , + 5 / 1) ∷ (+ 6 / 1 , + 6 / 1) ∷ []) ≡ + 1 / 10
wape-rest = refl

wape-pooled-le : wape rows ℚ.≤ + 1 / 5 ⊔ + 1 / 10
wape-pooled-le = from-yes (wape rows ≤? (+ 1 / 5 ⊔ + 1 / 10))

-- A series that counts the days: the naive forecast for day 10 is day 3; the level on day 28 is
-- the mean of days 21, 14, 7 and 0.
days : Series
days t = + t / 1

naive-10 : seasonalNaive days 10 ≡ + 3 / 1
naive-10 = refl

level-28 : lagMean days 28 ≡ + 21 / 2
level-28 = refl

-- A weekly series: the day of the week.
weekday : Series
weekday t = + (t % 7) / 1

naive-weekly : seasonalNaive weekday 12 ≡ weekday 12
naive-weekly = refl

-- Five rows split at day 5.
split-train : train 5 (1 ∷ 7 ∷ 3 ∷ 5 ∷ 9 ∷ []) ≡ 1 ∷ 3 ∷ []
split-train = refl

split-test : test 5 (1 ∷ 7 ∷ 3 ∷ 5 ∷ 9 ∷ []) ≡ 7 ∷ 5 ∷ 9 ∷ []
split-test = refl

-- A slot of 20 million viewers, three channels, a universe of 100 million.
slotAudiences : List ℚ
slotAudiences = + 6 / 1 ∷ + 4 / 1 ∷ + 2 / 1 ∷ []

panel-shares : shares (+ 20 / 1) slotAudiences ≡ + 3 / 10 ∷ + 1 / 5 ∷ + 1 / 10 ∷ []
panel-shares = refl

panel-outside : outside (+ 20 / 1) slotAudiences ≡ + 2 / 5
panel-outside = refl

panel-rating : rating (+ 100 / 1) (+ 6 / 1) ≡ + 3 / 50
panel-rating = refl

panel-put : put (+ 100 / 1) (+ 20 / 1) ≡ + 1 / 5
panel-put = refl

over-pool : countOver ((+ 10 / 1 , + 6 / 1 ∷ + 5 / 1 ∷ []) ∷ (+ 10 / 1 , + 3 / 1 ∷ []) ∷ []) ≡ 1ℚ
over-pool = refl

-- JCS with weights exp(u) = 1, 2 and 1/2, and a pool forecast of 9 million.
weights : List ℚ
weights = 1ℚ ∷ + 2 / 1 ∷ + 1 / 2 ∷ []

jcs-shares : jcsShares weights ≡ + 2 / 9 ∷ + 4 / 9 ∷ + 1 / 9 ∷ []
jcs-shares = refl

jcs-outside : jcsOutside weights ≡ + 2 / 9
jcs-outside = refl

jcs-forecast : jcsForecast (+ 9 / 1) weights ≡ + 2 / 1 ∷ + 4 / 1 ∷ 1ℚ ∷ []
jcs-forecast = refl

jcs-winner-9 : winner (jcsForecast (+ 9 / 1) weights) ≡ 1
jcs-winner-9 = refl

-- A rival of weight 3/2 joins: the first channel falls from 2/9 to 1/6.
jcs-rival-3/2 : jcsShare (+ 3 / 2 ∷ weights) 1ℚ ≡ + 1 / 6
jcs-rival-3/2 = refl

-- The first of two equal maxima wins, as pandas' idxmax.
winner-tie : winner (+ 3 / 1 ∷ + 5 / 1 ∷ + 5 / 1 ∷ 1ℚ ∷ []) ≡ 1
winner-tie = refl

accuracy-4 : accuracy ((1 , 1) ∷ (0 , 2) ∷ (2 , 2) ∷ (1 , 1) ∷ []) ≡ + 3 / 4
accuracy-4 = refl

-- A tree of depth 2 and a constant tree, on a row with x₀ = 1 and x₁ = 2.
tree : Tree
tree = node 0 (+ 1 / 2) (leaf (- 1ℚ)) (node 1 (+ 3 / 1) (leaf (+ 2 / 1)) (leaf (+ 4 / 1)))

row : Features
row 0 = 1ℚ
row _ = + 2 / 1

tree-eval : eval row tree ≡ + 2 / 1
tree-eval = refl

tree-lo : lo tree ≡ - 1ℚ
tree-lo = refl

tree-hi : hi tree ≡ + 4 / 1
tree-hi = refl

ensemble : predict (+ 1 / 2) (tree ∷ leaf (+ 1 / 4) ∷ []) row ≡ + 11 / 4
ensemble = refl
