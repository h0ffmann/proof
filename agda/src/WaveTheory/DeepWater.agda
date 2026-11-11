{-# OPTIONS --safe --without-K #-}

-- The deep-water limit of linear wave theory, for every `TanhModel`. New: the Lean original
-- has only the bounds c/2 ≤ c_g ≤ c and σ² ≤ g k.
--
-- A `TanhModel` reaches 1 at a finite argument `sat` (the clamped Padé model at 3). Above it the
-- dispersion relation is exactly the deep-water law σ² = g k, and then
--
--     c_g = c / 2,   c σ = g   (c = g / σ),   c² k = g.
--
-- For the true tanh these hold only in the limit k h → ∞; here they hold exactly in the
-- saturated regime of the model. The statements are about the model, not about tanh.
module WaveTheory.DeepWater where

open import Data.Product using (_×_; _,_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _<_)
open import Data.Rational.Properties using (*-identityʳ)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong)

open import OceanWaves.Order
open import OceanWaves.Dispersion

module _ (M : TanhModel) (W : Medium) where
  open TanhModel M
  open Medium W

  -- n = 1/2 in the saturated regime.
  nFactor-deep : ∀ {x} → sat ≤ x → nFactor M W x ≡ 1ℚ /₀ 2ℚ
  nFactor-deep {x} hx =
    trans (cong (λ t → (1ℚ + x * (1ℚ - t * t) /₀ t) /₀ 2ℚ) (T-sat x hx))
          (solve 3 (λ x i j → (con 1ℚ :+ x :* (con 1ℚ :- con 1ℚ :* con 1ℚ) :* i) :* j := con 1ℚ :* j)
             refl x (inv₀ 1ℚ) (inv₀ 2ℚ))

  -- c_g = c / 2 in deep water: the energy travels at half the phase speed.
  groupSpeed-deep : ∀ σ {k} → sat ≤ k * h → groupSpeed M W σ k ≡ phaseSpeed M W σ k /₀ 2ℚ
  groupSpeed-deep σ {k} hk =
    trans (cong (_* phaseSpeed M W σ k) (nFactor-deep hk))
          (solve 2 (λ c i → con 1ℚ :* i :* c := c :* i) refl (phaseSpeed M W σ k) (inv₀ 2ℚ))

  -- c σ = g for the exact root of the deep-water law: a longer period gives a faster wave
  -- (c = g T / 2π).
  phaseSpeed-deep : ∀ {σ k} → 0ℚ < k → sat ≤ k * h → σ * σ ≡ sigma2 M W k →
    phaseSpeed M W σ k * σ ≡ g
  phaseSpeed-deep {σ} {k} hk hs hd =
    trans (solve 3 (λ s i u → s :* i :* s := s :* s :* i) refl σ (inv₀ k) σ)
    (trans (cong (_* inv₀ k) (trans hd (sigma2-deep-exact M W hs)))
    (trans (solve 3 (λ g k i → g :* k :* i := g :* (k :* i)) refl g k (inv₀ k))
    (trans (cong (g *_) (inv₀-inverse k (<⇒≢0 hk))) (*-identityʳ g))))

  -- c² k = g at the exact root: Lean's `phaseSpeed-sq-le-deep` with equality.
  phaseSpeed-sq-deep : ∀ {σ k} → 0ℚ < k → sat ≤ k * h → σ * σ ≡ sigma2 M W k →
    phaseSpeed M W σ k * phaseSpeed M W σ k * k ≡ g
  phaseSpeed-sq-deep {σ} {k} hk hs hd =
    trans (solve 3 (λ s i k → s :* i :* (s :* i) :* k := s :* i :* s :* (k :* i)) refl σ (inv₀ k) k)
    (trans (cong (phaseSpeed M W σ k * σ *_) (inv₀-inverse k (<⇒≢0 hk)))
    (trans (*-identityʳ _) (phaseSpeed-deep {σ} {k} hk hs hd)))

  -- In deep water the group speed is g / (2σ): c_g σ = g / 2.
  groupSpeed-deep-σ : ∀ {σ k} → 0ℚ < k → sat ≤ k * h → σ * σ ≡ sigma2 M W k →
    groupSpeed M W σ k * σ ≡ g /₀ 2ℚ
  groupSpeed-deep-σ {σ} {k} hk hs hd =
    trans (cong (_* σ) (groupSpeed-deep σ {k} hs))
    (trans (solve 3 (λ c j s → c :* j :* s := c :* s :* j) refl (phaseSpeed M W σ k) (inv₀ 2ℚ) σ)
           (cong (_/₀ 2ℚ) (phaseSpeed-deep {σ} {k} hk hs hd)))
