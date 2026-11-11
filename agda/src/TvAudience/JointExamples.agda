{-# OPTIONS --safe --without-K #-}

-- Examples of `TvAudience.Joint`, every one by `refl`.
--
-- * `bigShow`: three channels with actual audiences 3, 2, 1 (total 6). A big show takes viewers
--   that no channel's own model sees, so each channel is over-forecast by 1 (4, 3, 2). With the
--   actual pool the joint step removes the whole error (SSE 3 to 0); with a pool forecast of 7
--   (ε = 1, S = 3) it leaves 1/3, and 3 · (3 - 1/3) = 8 = 3² - 1².
-- * `uneven`: two channels, the second over-forecast by 2 and the first exact. The total error
--   falls (4 to 2), but the first channel goes from 0 to 1: per channel, the band of
--   `channel-no-worse` is needed.
-- * `lopsided`: a pool forecast that is worse than the sum of the channels (ε = 2, S = 1) makes
--   the joint estimate worse (1 to 5/2): the condition |ε| ≤ |S| of `joint-le` is needed.
module TvAudience.JointExamples where

open import Data.List using (List; []; _∷_)
open import Data.Product using (_,_)
open import Data.Nat using (ℕ)
open import Data.Integer using (+_; -[1+_])
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _/_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import TvAudience.Joint

n : ℕ → ℚ
n k = + k / 1

bigShow : List Row
bigShow = (n 3 , n 4) ∷ (n 2 , n 3) ∷ (n 1 , n 2) ∷ []

bigShow-alone : sse bigShow ≡ n 3
bigShow-alone = refl

bigShow-bias : bias bigShow ≡ n 3
bigShow-bias = refl

bigShow-exact : reconcile (n 6) bigShow ≡ (n 3 , n 3) ∷ (n 2 , n 2) ∷ (n 1 , n 1) ∷ []
bigShow-exact = refl

bigShow-joint : sse (reconcile (n 6) bigShow) ≡ 0ℚ
bigShow-joint = refl

bigShow-pool7 : sse (reconcile (n 7) bigShow) ≡ + 1 / 3
bigShow-pool7 = refl

bigShow-coherent : fsum (reconcile (n 7) bigShow) ≡ n 7
bigShow-coherent = refl

uneven : List Row
uneven = (1ℚ , 1ℚ) ∷ (1ℚ , n 3) ∷ []

uneven-joint : reconcile (n 2) uneven ≡ (1ℚ , 0ℚ) ∷ (1ℚ , n 2) ∷ []
uneven-joint = refl

uneven-sse : sse uneven ≡ n 4
uneven-sse = refl

uneven-sse-joint : sse (reconcile (n 2) uneven) ≡ n 2
uneven-sse-joint = refl

-- The first channel's error goes from 0 to -1.
uneven-first : err (shiftRow (step (n 2) uneven) (1ℚ , 1ℚ)) ≡ -[1+ 0 ] / 1
uneven-first = refl

lopsided : List Row
lopsided = (1ℚ , n 2) ∷ (1ℚ , 1ℚ) ∷ []

lopsided-alone : sse lopsided ≡ 1ℚ
lopsided-alone = refl

lopsided-joint : sse (reconcile (n 4) lopsided) ≡ + 5 / 2
lopsided-joint = refl
