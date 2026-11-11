{-# OPTIONS --safe --without-K #-}

-- Wave action on a current. New: the Lean original has no current.
--
-- On a current U (here one component, along the wave), the absolute frequency is
-- ω = σ + k U, with σ the intrinsic frequency of linear theory. Energy E is not conserved on a
-- current, but the action A = E / σ is (Bretherton and Garrett 1968): this is why WAVEWATCH III
-- solves the balance equation for the action density N and not for the energy. In a steady
-- one-dimensional current with no sources the action flux (c_g + U) A is the same everywhere.
--
-- The statements here are algebra on exact rationals: the Doppler relation, the energy that
-- the action flux gives at a second station, that with no current the action flux and the
-- energy flux say the same thing, and that a current at or above -c_g blocks the waves.
module WaveTheory.WaveAction where

open import Data.Product using (_×_; _,_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; _≤_; _<_)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; <⇒≤; *-identityʳ; *-monoʳ-≤-nonNeg; *-zeroˡ)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; :-_; con)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong; cong₂; subst)

open import OceanWaves.Order
open import WaveTheory.Algebra

-- ---------------------------------------------------------------------------------------------
-- The Doppler relation

-- The absolute frequency of a wave of intrinsic frequency σ and wave number k on a current U.
absolute : ℚ → ℚ → ℚ → ℚ
absolute σ k U = σ + k * U

-- The intrinsic frequency from the absolute one.
intrinsic : ℚ → ℚ → ℚ → ℚ
intrinsic ω k U = ω - k * U

doppler-round : ∀ σ k U → intrinsic (absolute σ k U) k U ≡ σ
doppler-round = solve 3 (λ s k u → s :+ k :* u :- k :* u := s) refl

-- With no current the two frequencies are one.
doppler-still : ∀ σ k → absolute σ k 0ℚ ≡ σ
doppler-still = solve 2 (λ s k → s :+ k :* con 0ℚ := s) refl

-- On a following current (k U ≥ 0) the intrinsic frequency is at most the absolute one.
intrinsic-following : ∀ ω {k U} → 0ℚ ≤ k * U → intrinsic ω k U ≤ ω
intrinsic-following ω {k} {U} h =
  by-diff (k * U) (solve 2 (λ w x → w :- (w :- x) := x) refl ω (k * U)) h

-- ---------------------------------------------------------------------------------------------
-- Action and its flux

-- The action of the energy E at the intrinsic frequency σ.
action : ℚ → ℚ → ℚ
action E σ = E /₀ σ

action-energy : ∀ E {σ} → 0ℚ < σ → action E σ * σ ≡ E
action-energy E h = div-mul-cancel E (<⇒≢0 h)

-- The action flux of a train with group speed c_g on a current U.
actionFlux : ℚ → ℚ → ℚ → ℚ → ℚ
actionFlux cg U E σ = (cg + U) * action E σ

-- What a conserved action flux says about the energy at a second station:
-- E₂ σ₁ (c_g₂ + U₂) = E₁ σ₂ (c_g₁ + U₁), that is E₂ = E₁ (σ₂ / σ₁) (c_g₁ + U₁) / (c_g₂ + U₂).
energy-from-action : ∀ {cg₁ U₁ E₁ σ₁ cg₂ U₂ E₂ σ₂} → 0ℚ < σ₁ → 0ℚ < σ₂ →
  actionFlux cg₁ U₁ E₁ σ₁ ≡ actionFlux cg₂ U₂ E₂ σ₂ →
  E₂ * σ₁ * (cg₂ + U₂) ≡ E₁ * σ₂ * (cg₁ + U₁)
energy-from-action {cg₁} {U₁} {E₁} {σ₁} {cg₂} {U₂} {E₂} {σ₂} h1 h2 flux = begin
  E₂ * σ₁ * (cg₂ + U₂)                         ≡⟨ cong (λ e → e * σ₁ * (cg₂ + U₂)) (sym (action-energy E₂ h2)) ⟩
  action E₂ σ₂ * σ₂ * σ₁ * (cg₂ + U₂)          ≡⟨ solve 4 (λ a s t c → a :* s :* t :* c := c :* a :* s :* t) refl (action E₂ σ₂) σ₂ σ₁ (cg₂ + U₂) ⟩
  actionFlux cg₂ U₂ E₂ σ₂ * σ₂ * σ₁            ≡⟨ cong (λ f → f * σ₂ * σ₁) (sym flux) ⟩
  actionFlux cg₁ U₁ E₁ σ₁ * σ₂ * σ₁            ≡⟨ solve 4 (λ c a s t → c :* a :* s :* t := a :* t :* s :* c) refl (cg₁ + U₁) (action E₁ σ₁) σ₂ σ₁ ⟩
  action E₁ σ₁ * σ₁ * σ₂ * (cg₁ + U₁)          ≡⟨ cong (λ e → e * σ₂ * (cg₁ + U₁)) (action-energy E₁ h1) ⟩
  E₁ * σ₂ * (cg₁ + U₁)                         ∎
  where
  open import Relation.Binary.PropositionalEquality using (module ≡-Reasoning)
  open ≡-Reasoning

-- With no current, σ is the same at both stations (ω is conserved and ω = σ), and the action
-- flux is the energy flux divided by σ: shoaling (`WaveTheory.Shoaling`) is the special case.
no-current-energy-flux : ∀ {cg₁ E₁ cg₂ E₂ σ} → 0ℚ < σ →
  actionFlux cg₁ 0ℚ E₁ σ ≡ actionFlux cg₂ 0ℚ E₂ σ → E₁ * cg₁ ≡ E₂ * cg₂
no-current-energy-flux {cg₁} {E₁} {cg₂} {E₂} {σ} h flux = *-cancelʳ-≡ h lhs
  where
  open import Relation.Binary.PropositionalEquality using (module ≡-Reasoning)
  open ≡-Reasoning
  -- energy-from-action with σ₁ = σ₂ = σ and U = 0.
  e = energy-from-action {cg₁} {0ℚ} {E₁} {σ} {cg₂} {0ℚ} {E₂} {σ} h h flux
  lhs : E₁ * cg₁ * σ ≡ E₂ * cg₂ * σ
  lhs = begin
    E₁ * cg₁ * σ         ≡⟨ solve 3 (λ e c s → e :* c :* s := e :* s :* (c :+ con 0ℚ)) refl E₁ cg₁ σ ⟩
    E₁ * σ * (cg₁ + 0ℚ)  ≡⟨ sym e ⟩
    E₂ * σ * (cg₂ + 0ℚ)  ≡⟨ solve 3 (λ e c s → e :* s :* (c :+ con 0ℚ) := e :* c :* s) refl E₂ cg₂ σ ⟩
    E₂ * cg₂ * σ         ∎

-- Blocking: where the current runs against the waves at least as fast as they travel
-- (c_g + U ≤ 0), no action is carried in the direction of the waves.
blocked : ∀ {cg U E σ} → cg + U ≤ 0ℚ → 0ℚ ≤ E → 0ℚ ≤ σ → actionFlux cg U E σ ≤ 0ℚ
blocked {cg} {U} {E} {σ} hb hE hσ =
  ≤-trans (*-monoʳ-≤-nonNeg (action E σ) {{nonNegative (div-nonneg hE hσ)}} hb)
          (≤-reflexive (*-zeroˡ (action E σ)))
