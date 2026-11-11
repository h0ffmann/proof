{-# OPTIONS --safe --without-K #-}

-- The forecasting pipeline of `tv-audience/python/experiment.py` for JCS and the neurosymbolic
-- JCS, end to end, as one Agda function:
--
--   line-up ──▶ rival features ──▶ standardised features z ──▶ utility u (linear + network)
--     ──▶ weight exp(u) ──▶ shares (one softmax per slot, outside option)
--   pool history ──▶ tree ensemble on the log change ──▶ pool forecast exp(level + trees)
--     ──▶ audience = pool forecast × share ──▶ WAPE, slot winner, coherence count
--
-- The exponential and the activation are arguments: ℚ has neither exp nor tanh. A theorem that
-- needs them asks only what the real ones satisfy: exp is positive and strictly increasing
-- (`ExpLike`), tanh is bounded by 1. The fitted numbers (the weights, the trees, the scaler's
-- means and deviations) are arguments too, so every theorem holds for the parameters the
-- Python fits, and for any others.
--
-- The theorems, for every model and every input: every forecast is ≥ 0; the forecasts of a slot
-- and its outside audience add up to the pool forecast, so no slot is over its pool forecast and
-- the coherence count is 0; the predicted winner of a slot is the channel with the largest
-- utility, whatever the pool model; and with the network's output weights at 0 the neurosymbolic
-- pipeline gives the JCS pipeline's forecasts.
module TvAudience.Pipeline where

open import Data.Bool using (if_then_else_)
open import Data.List using (List; []; _∷_; map; _++_; concat)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.Nat using (ℕ; suc)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational
  using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _<_)
  renaming (_/_ to _÷_)
open import Data.Integer using (+_)
open import Data.Rational.Properties
  using (<⇒≤; <-irrefl; <-asym; <-cmp; _<?_)
open import Relation.Binary.Definitions using (tri<; tri≈; tri>)
open import Relation.Nullary using (does; Dec; yes; no; ¬_)
open import Relation.Nullary.Decidable using (dec-true; dec-false)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst)

open import TvAudience.Wape using (Row; wape)
open import TvAudience.Panel using (Slot; Coherent; countOver; countOver-coherent)
open import TvAudience.Features using (Programme; Rival; slotFeatures; sameGenre; rivalSum; rivalMax)
open import TvAudience.Jcs using (jcsShares; jcsOutside; jcsForecast; NonNeg; jcs-coherent)
open import TvAudience.JcsTheory using (jcs-accounting)
open import TvAudience.Winner using (winner; go; jcs-winner)
open import TvAudience.Neural
  using (NsParams; ns; W2; nsUtility; linearUtility; standardise; ns-nests-jcs)
open import TvAudience.Trees using (Tree; Features; predict)
open import FatTails.Sample using (sum)

-- What the real exponential satisfies, and all the theorems ask of it.
record ExpLike (e : ℚ → ℚ) : Set where
  field
    pos  : ∀ u → 0ℚ < e u
    mono : ∀ {u v} → u < v → e u < e v
open ExpLike public

-- ---------------------------------------------------------------------------------------------
-- Features

-- A channel's raw share features: its own (the log-odds lags, the trend, the holiday flag,
-- one-hot columns, computed upstream) followed by its rival features from the line-up.
channelRaw : List ℚ → Rival → List ℚ
channelRaw own r = own ++ ((+ sameGenre r ÷ 1) ∷ rivalMax r ∷ rivalSum r ∷ [])

-- The scaler's means and deviations, one per column.
standardiseAll : List ℚ → List ℚ → List ℚ → List ℚ
standardiseAll (μ ∷ μs) (σ ∷ σs) (x ∷ xs) = standardise μ σ x ∷ standardiseAll μs σs xs
standardiseAll _        _        _        = []

-- The z of every channel of a slot: own features in the slot's channel order, and its line-up.
slotZ : List ℚ → List ℚ → List (List ℚ) → List Programme → List (List ℚ)
slotZ μs σs owns lineup = zipWith (λ own r → standardiseAll μs σs (channelRaw own r)) owns (slotFeatures lineup)
  where
  zipWith : ∀ {A B C : Set} → (A → B → C) → List A → List B → List C
  zipWith f (a ∷ as) (b ∷ bs) = f a b ∷ zipWith f as bs
  zipWith f _        _        = []

-- ---------------------------------------------------------------------------------------------
-- The model

record Model : Set where
  constructor model
  field
    e         : ℚ → ℚ           -- the exponential
    act       : ℚ → ℚ           -- the network's activation (tanh)
    params    : NsParams        -- the utility (JCS when W2 = 0)
    poolBase  : ℚ               -- the pool model: base score and trees on the log change
    poolTrees : List Tree
open Model public

-- One slot's input: the pool's 4-week log level and the pool model's features, and each
-- channel's standardised share features.
record SlotIn : Set where
  constructor slotIn
  field
    level : ℚ
    poolX : Features
    zs    : List (List ℚ)
open SlotIn public

utilities : Model → SlotIn → List ℚ
utilities M d = map (nsUtility (act M) (params M)) (zs d)

weightsOf : Model → SlotIn → List ℚ
weightsOf M d = map (e M) (utilities M d)

poolHat : Model → SlotIn → ℚ
poolHat M d = e M (level d + predict (poolBase M) (poolTrees M) (poolX d))

forecastSlot : Model → SlotIn → List ℚ
forecastSlot M d = jcsForecast (poolHat M d) (weightsOf M d)

-- ---------------------------------------------------------------------------------------------
-- Evaluation

-- Each slot with its actual audiences, channel by channel.
Scored : Set
Scored = SlotIn × List ℚ

rowsOf : Model → List Scored → List Row
rowsOf M []              = []
rowsOf M ((d , ys) ∷ ss) = pairs ys (forecastSlot M d) ++ rowsOf M ss
  where
  pairs : List ℚ → List ℚ → List Row
  pairs (y ∷ ys′) (f ∷ fs) = (y , f) ∷ pairs ys′ fs
  pairs _         _        = []

pipelineWape : Model → List Scored → ℚ
pipelineWape M ss = wape (rowsOf M ss)

-- The slots against the model's own pool forecast.
againstPoolHat : Model → List SlotIn → List Slot
againstPoolHat M = map (λ d → (poolHat M d , forecastSlot M d))

winners : Model → List Scored → List (ℕ × ℕ)
winners M = map (λ { (d , ys) → (winner ys , winner (forecastSlot M d)) })

-- ---------------------------------------------------------------------------------------------
-- Positivity

private
  map-pos : ∀ {e} → ExpLike e → ∀ us → NonNeg (map e us)
  map-pos E []       = []
  map-pos E (u ∷ us) = <⇒≤ (pos E u) ∷ map-pos E us

weights-nonneg : ∀ M d → ExpLike (e M) → NonNeg (weightsOf M d)
weights-nonneg M d E = map-pos E (utilities M d)

poolHat-pos : ∀ M d → ExpLike (e M) → 0ℚ < poolHat M d
poolHat-pos M d E = pos E _

-- ---------------------------------------------------------------------------------------------
-- Coherence

pipeline-coherent : ∀ M d → ExpLike (e M) → Coherent (poolHat M d , forecastSlot M d)
pipeline-coherent M d E = jcs-coherent (poolHat M d) (weightsOf M d) (<⇒≤ (poolHat-pos M d E)) (weights-nonneg M d E)

pipeline-accounting : ∀ M d → ExpLike (e M) →
  sum (forecastSlot M d) + poolHat M d * jcsOutside (weightsOf M d) ≡ poolHat M d
pipeline-accounting M d E = jcs-accounting (poolHat M d) (weightsOf M d) (weights-nonneg M d E)

pipeline-countOver : ∀ M ds → ExpLike (e M) → countOver (againstPoolHat M ds) ≡ 0ℚ
pipeline-countOver M ds E = countOver-coherent (againstPoolHat M ds) (go′ ds)
  where
  go′ : ∀ ds → All Coherent (againstPoolHat M ds)
  go′ []       = []
  go′ (d ∷ ds) = pipeline-coherent M d E ∷ go′ ds

-- ---------------------------------------------------------------------------------------------
-- The winner is the largest utility

private
  mono-does : ∀ {f : ℚ → ℚ} → (∀ {u v} → u < v → f u < f v) → ∀ v x → does (f v <? f x) ≡ does (v <? x)
  mono-does {f} m v x = case (v <? x)
    where
    case : Dec (v < x) → does (f v <? f x) ≡ does (v <? x)
    case (yes p) = trans (dec-true (f v <? f x) (m {v} {x} p)) (sym (dec-true (v <? x) p))
    case (no ¬p) = trans (dec-false (f v <? f x) never) (sym (dec-false (v <? x) ¬p))
      where
      never : ¬ (f v < f x)
      never q with <-cmp v x
      ... | tri< v<x _ _ = ¬p v<x
      ... | tri≈ _ refl _ = <-irrefl refl q
      ... | tri> _ _ x<v = <-asym q (m {x} {v} x<v)

  go-mono : ∀ {f : ℚ → ℚ} → (∀ {u v} → u < v → f u < f v) → ∀ i b v xs → go i b (f v) (map f xs) ≡ go i b v xs
  go-mono m i b v []       = refl
  go-mono {f} m i b v (x ∷ xs) =
    trans (cong (λ t → if t then go (suc i) i (f x) (map f xs) else go (suc i) b (f v) (map f xs)) (mono-does {f} m v x))
          (cong₂ (λ p q → if does (v <? x) then p else q) (go-mono {f} m (suc i) i x xs) (go-mono {f} m (suc i) b v xs))

-- A strictly increasing map keeps the winner.
winner-mono : ∀ {f : ℚ → ℚ} → (∀ {u v} → u < v → f u < f v) → ∀ xs → winner (map f xs) ≡ winner xs
winner-mono m []       = refl
winner-mono {f} m (x ∷ xs) = go-mono {f} m 1 0 x xs

pipeline-winner : ∀ M d → ExpLike (e M) → winner (forecastSlot M d) ≡ winner (utilities M d)
pipeline-winner M d E =
  trans (jcs-winner (poolHat M d) (weightsOf M d) (poolHat-pos M d E) (weights-nonneg M d E))
        (winner-mono (mono E) (utilities M d))

-- ---------------------------------------------------------------------------------------------
-- The neurosymbolic pipeline nests the JCS pipeline

-- The same model with the network switched off.
withoutNetwork : Model → Model
withoutNetwork M = record M { params = record (params M) { W2 = [] } }

pipeline-nests : ∀ M d → All (_≡ 0ℚ) (W2 (params M)) → forecastSlot M d ≡ forecastSlot (withoutNetwork M) d
pipeline-nests M d h = cong (jcsForecast (poolHat M d)) (cong (map (e M)) (same (zs d)))
  where
  P = params M
  same : ∀ zs′ → map (nsUtility (act M) P) zs′ ≡ map (nsUtility (act M) (params (withoutNetwork M))) zs′
  same []        = refl
  same (z ∷ zs′) =
    cong₂ _∷_ (trans (ns-nests-jcs (act M) P z h) (sym (ns-nests-jcs (act M) (params (withoutNetwork M)) z [])))
              (same zs′)
