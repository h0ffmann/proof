{-# OPTIONS --safe --without-K #-}

-- Depth refraction over straight, parallel depth contours: Snell's law. New: the Lean
-- original propagates in one dimension only.
--
-- θ is the angle between the wave ray and the normal to the depth contours. Along the ray the
-- wave number component along the contours is constant (the frequency is constant and the
-- medium does not change along the contours), so
--
--     sin θ / c = const,   or   k sin θ = const.
--
-- ℚ has no sine. A sine here is a rational s, and the statements say what the law does to s:
-- it shrinks where waves slow down (rays turn towards the normal, so crests turn parallel to
-- the coast), it stays a sine (|s| ≤ 1) in that case, and it can pass 1 where waves speed up
-- (no refracted wave: total reflection at a depth step, or a caustic). With the dispersion
-- relation of a `TanhModel`, shallower water gives a larger k for the same σ, so a wave that
-- comes into shallower water always turns towards the normal.
module WaveTheory.Refraction where

open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _<_; _≤?_; _<?_)
open import Data.Rational.Base using (nonNegative; positive)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; <⇒≤; <-≤-trans; ≤-<-trans; <-irrefl; ≰⇒>;
         *-monoˡ-≤-nonNeg; *-monoʳ-≤-nonNeg)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Nullary using (Dec; yes; no; contradiction)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong; subst)

open import OceanWaves.Order
open import OceanWaves.Dispersion
open import WaveTheory.Algebra

-- ---------------------------------------------------------------------------------------------
-- Snell's law on speeds

-- The sine of the ray angle in the second medium.
snell : ℚ → ℚ → ℚ → ℚ
snell s₁ c₁ c₂ = s₁ * c₂ /₀ c₁

-- sin θ / c is the same on both sides (cross-multiplied).
snell-invariant : ∀ s₁ {c₁} c₂ → 0ℚ < c₁ → snell s₁ c₁ c₂ * c₁ ≡ s₁ * c₂
snell-invariant s₁ c₂ h1 = div-mul-cancel (s₁ * c₂) (<⇒≢0 h1)

-- Where waves slow down, the ray turns towards the normal: 0 ≤ s₂ ≤ s₁.
snell-toward-normal : ∀ {s₁ c₁ c₂} → 0ℚ ≤ s₁ → 0ℚ ≤ c₂ → 0ℚ < c₁ → c₂ ≤ c₁ →
  0ℚ ≤ snell s₁ c₁ c₂ × snell s₁ c₁ c₂ ≤ s₁
snell-toward-normal {s₁} {c₁} {c₂} hs h2 h1 h21 =
  div-nonneg (*-nonneg hs h2) (<⇒≤ h1) ,
  div-le-of-le-mul {a = s₁ * c₂} {b = c₁} {c = s₁} h1 (*-monoˡ-≤-nonNeg s₁ {{nonNegative hs}} h21)

-- So a sine stays a sine.
snell-stays-sine : ∀ {s₁ c₁ c₂} → 0ℚ ≤ s₁ → s₁ ≤ 1ℚ → 0ℚ ≤ c₂ → 0ℚ < c₁ → c₂ ≤ c₁ →
  snell s₁ c₁ c₂ ≤ 1ℚ
snell-stays-sine hs hs1 h2 h1 h21 = ≤-trans (proj₂ (snell-toward-normal hs h2 h1 h21)) hs1

-- Where waves speed up, the ray turns away from the normal: s₁ ≤ s₂.
snell-away : ∀ {s₁ c₁ c₂} → 0ℚ ≤ s₁ → 0ℚ < c₁ → c₁ ≤ c₂ → s₁ ≤ snell s₁ c₁ c₂
snell-away {s₁} {c₁} {c₂} hs h1 h12 =
  le-div-of-mul-le {a = s₁ * c₂} {b = c₁} {c = s₁} h1 (*-monoˡ-≤-nonNeg s₁ {{nonNegative hs}} h12)

-- Two refractions are one: the law depends only on the end speeds.
snell-compose : ∀ s₁ {c₁ c₂} c₃ → 0ℚ < c₁ → 0ℚ < c₂ → snell (snell s₁ c₁ c₂) c₂ c₃ ≡ snell s₁ c₁ c₃
snell-compose s₁ {c₁} {c₂} c₃ h1 h2 = *-cancelʳ-≡ (*-pos h1 h2) (begin
  u * (c₁ * c₂)   ≡⟨ solve 3 (λ u a b → u :* (a :* b) := u :* b :* a) refl u c₁ c₂ ⟩
  u * c₂ * c₁     ≡⟨ cong (_* c₁) (snell-invariant t c₃ h2) ⟩
  t * c₃ * c₁     ≡⟨ solve 3 (λ t x a → t :* x :* a := t :* a :* x) refl t c₃ c₁ ⟩
  t * c₁ * c₃     ≡⟨ cong (_* c₃) (snell-invariant s₁ c₂ h1) ⟩
  s₁ * c₂ * c₃    ≡⟨ solve 3 (λ s b x → s :* b :* x := s :* x :* b) refl s₁ c₂ c₃ ⟩
  s₁ * c₃ * c₂    ≡⟨ cong (_* c₂) (sym (snell-invariant s₁ c₃ h1)) ⟩
  v * c₁ * c₂     ≡⟨ solve 3 (λ v a b → v :* a :* b := v :* (a :* b)) refl v c₁ c₂ ⟩
  v * (c₁ * c₂)   ∎)
  where
  open import Relation.Binary.PropositionalEquality using (module ≡-Reasoning)
  open ≡-Reasoning
  t = snell s₁ c₁ c₂
  u = snell t c₂ c₃
  v = snell s₁ c₁ c₃

-- A wave at 60° or so (s₁ = 3/4) that comes into water where it travels twice as fast has no
-- refracted ray: the law asks for a sine of 3/2.
total-reflection : 1ℚ < snell (lit 3 /₀ lit 4) 1ℚ 2ℚ
total-reflection = from-yes (1ℚ <? snell (lit 3 /₀ lit 4) 1ℚ 2ℚ)
  where open import Relation.Nullary.Decidable using (from-yes)

-- ---------------------------------------------------------------------------------------------
-- Snell's law with the dispersion relation

-- A medium of depth h with gravity g.
medium : (g h : ℚ) → 0ℚ < g → 0ℚ < h → Medium
medium g h hg hh = record { g = g ; h = h ; g-pos = hg ; h-pos = hh }

module _ (M : TanhModel) (g : ℚ) (hg : 0ℚ < g) where
  open TanhModel M

  -- With c = σ / k, Snell's law is k sin θ = const: the wave number along the contours.
  alongshore-k : ∀ {σ k₁ k₂} s₁ → 0ℚ < σ → 0ℚ < k₁ → 0ℚ < k₂ →
    k₂ * snell s₁ (σ /₀ k₁) (σ /₀ k₂) ≡ k₁ * s₁
  alongshore-k {σ} {k₁} {k₂} s₁ hσ h1 h2 = *-cancelʳ-≡ c1-pos (begin
    k₂ * s₂ * c₁           ≡⟨ solve 3 (λ k s c → k :* s :* c := k :* (s :* c)) refl k₂ s₂ c₁ ⟩
    k₂ * (s₂ * c₁)         ≡⟨ cong (k₂ *_) (snell-invariant s₁ c₂ c1-pos) ⟩
    k₂ * (s₁ * c₂)         ≡⟨ solve 4 (λ k s σ i → k :* (s :* (σ :* i)) := s :* σ :* (k :* i)) refl k₂ s₁ σ (inv₀ k₂) ⟩
    s₁ * σ * (k₂ * inv₀ k₂) ≡⟨ cong (s₁ * σ *_) (inv₀-inverse k₂ (<⇒≢0 h2)) ⟩
    s₁ * σ * 1ℚ            ≡⟨ cong (s₁ * σ *_) (sym (inv₀-inverse k₁ (<⇒≢0 h1))) ⟩
    s₁ * σ * (k₁ * inv₀ k₁) ≡⟨ solve 4 (λ k s σ i → s :* σ :* (k :* i) := k :* s :* (σ :* i)) refl k₁ s₁ σ (inv₀ k₁) ⟩
    k₁ * s₁ * c₁           ∎)
    where
    open import Relation.Binary.PropositionalEquality using (module ≡-Reasoning)
    open ≡-Reasoning
    c₁ = σ /₀ k₁
    c₂ = σ /₀ k₂
    s₂ = snell s₁ c₁ c₂
    c1-pos = div-pos hσ h1

  -- Shallower water, shorter waves. If k₁ solves the dispersion relation for σ in depth h₁
  -- and k₂ in depth h₂ ≤ h₁, then k₁ ≤ k₂. The proof needs only that σ²(k) is strictly
  -- increasing in k and that T is monotone.
  shallower-shorter : ∀ {h₁ h₂ σ k₁ k₂} (hh₁ : 0ℚ < h₁) (hh₂ : 0ℚ < h₂) → h₂ ≤ h₁ →
    0ℚ ≤ k₁ → 0ℚ ≤ k₂ →
    σ * σ ≡ sigma2 M (medium g h₁ hg hh₁) k₁ → σ * σ ≡ sigma2 M (medium g h₂ hg hh₂) k₂ →
    k₁ ≤ k₂
  shallower-shorter {h₁} {h₂} {σ} {k₁} {k₂} hh₁ hh₂ h21 hk₁ hk₂ d₁ d₂ = go (k₁ ≤? k₂)
    where
    W₁ = medium g h₁ hg hh₁
    W₂ = medium g h₂ hg hh₂
    go : Dec (k₁ ≤ k₂) → k₁ ≤ k₂
    go (yes le) = le
    go (no  nle) = contradiction (≤-<-trans (≤-reflexive (trans (sym d₁) d₂)) lt) (<-irrefl refl)
      where
      k₂<k₁ = ≰⇒> nle
      -- σ²_{h₂}(k₂) < σ²_{h₂}(k₁) ≤ σ²_{h₁}(k₁)
      lt : sigma2 M W₂ k₂ < sigma2 M W₁ k₁
      lt = <-≤-trans (sigma2-strictMono M W₂ hk₂ k₂<k₁)
             (*-monoˡ-≤-nonNeg (g * k₁) {{nonNegative (*-nonneg (<⇒≤ hg) hk₁)}}
                (mono (k₁ * h₂) (k₁ * h₁) (*-nonneg hk₁ (<⇒≤ hh₂))
                      (*-monoˡ-≤-nonNeg k₁ {{nonNegative hk₁}} h21)))

  -- A wave that comes into shallower water turns towards the normal: the phase speed drops,
  -- and Snell's law shrinks the sine.
  shoaling-turns-to-normal : ∀ {h₁ h₂ σ k₁ k₂ s₁} (hh₁ : 0ℚ < h₁) (hh₂ : 0ℚ < h₂) → h₂ ≤ h₁ →
    0ℚ < σ → 0ℚ < k₁ → 0ℚ < k₂ → 0ℚ ≤ s₁ →
    σ * σ ≡ sigma2 M (medium g h₁ hg hh₁) k₁ → σ * σ ≡ sigma2 M (medium g h₂ hg hh₂) k₂ →
    0ℚ ≤ snell s₁ (σ /₀ k₁) (σ /₀ k₂) × snell s₁ (σ /₀ k₁) (σ /₀ k₂) ≤ s₁
  shoaling-turns-to-normal {h₁} {h₂} {σ} {k₁} {k₂} hh₁ hh₂ h21 hσ hk₁ hk₂ hs d₁ d₂ =
    snell-toward-normal hs (<⇒≤ (div-pos hσ hk₂)) (div-pos hσ hk₁) slower
    where
    k₁≤k₂ = shallower-shorter {σ = σ} hh₁ hh₂ h21 (<⇒≤ hk₁) (<⇒≤ hk₂) d₁ d₂
    slower : σ /₀ k₂ ≤ σ /₀ k₁
    slower = div-le-div-of-cross {a = σ} {b = k₂} {c = σ} {d = k₁} hk₂ hk₁
               (*-monoˡ-≤-nonNeg σ {{nonNegative (<⇒≤ hσ)}} k₁≤k₂)
