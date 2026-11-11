{-# OPTIONS --safe --without-K #-}

-- Time as a flat circle: the clock of the essay `papers/cycle/`, ported from
-- `cycle/lean/Cycle/Clock.lean`. The names follow Lean, with `-` for `_`.
--
-- A world has n + 1 moments. Time moves by one tick. The tick after the last moment is the
-- first moment again. This module proves:
--
-- * `tick-iterate`: after k ticks you are at (t + k) mod (n + 1).
-- * `eternal-return`: after n + 1 ticks every moment is itself again.
-- * `history-periodic`: the whole history repeats with period n + 1.
-- * `returns-forever`: every moment comes back after every multiple of n + 1 ticks.
module Cycle.Clock where

open import Data.Fin using (Fin; toℕ; fromℕ<)
open import Data.Fin.Properties using (toℕ-fromℕ<; toℕ-injective; toℕ<n)
open import Data.Nat using (ℕ; zero; suc; _+_; _*_; _%_)
open import Data.Nat.DivMod using (m%n<n; m<n⇒m%n≡m; [m+n]%n≡m%n; [m+kn]%n≡m%n; %-distribˡ-+; m%n%n≡m%n)
open import Data.Nat.Properties using (+-suc; +-assoc)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong; sym; trans; module ≡-Reasoning)
open ≡-Reasoning

-- One moment on a circle of n + 1 moments.
Moment : ℕ → Set
Moment n = Fin (suc n)

-- One tick of the clock: the moment after t. After the last moment comes the first.
tick : (n : ℕ) → Moment n → Moment n
tick n t = fromℕ< (m%n<n (suc (toℕ t)) (suc n))

-- `run n k t` applies `tick` k times, from t.
run : (n : ℕ) → ℕ → Moment n → Moment n
run n zero    t = t
run n (suc k) t = run n k (tick n t)

-- The moment k ticks after t0.
history : (n : ℕ) → Moment n → ℕ → Moment n
history n t0 k = run n k t0

-- ((a mod d) + k) mod d is (a + k) mod d.
private
  mod-add : ∀ a k d → ((a % suc d) + k) % suc d ≡ (a + k) % suc d
  mod-add a k d = begin
    ((a % suc d) + k) % suc d                    ≡⟨ %-distribˡ-+ (a % suc d) k (suc d) ⟩
    ((a % suc d % suc d) + (k % suc d)) % suc d  ≡⟨ cong (λ x → (x + (k % suc d)) % suc d) (m%n%n≡m%n a (suc d)) ⟩
    ((a % suc d) + (k % suc d)) % suc d          ≡⟨ sym (%-distribˡ-+ a k (suc d)) ⟩
    (a + k) % suc d                              ∎

  -- A moment is its own value mod n + 1.
  self-mod : ∀ n (t : Moment n) → toℕ t % suc n ≡ toℕ t
  self-mod n t = m<n⇒m%n≡m (toℕ<n t)

-- Closed form: k ticks after t is (t + k) mod (n + 1).
tick-iterate : ∀ n (t : Moment n) k → toℕ (run n k t) ≡ (toℕ t + k) % suc n
tick-iterate n t zero = begin
  toℕ t              ≡⟨ sym (self-mod n t) ⟩
  toℕ t % suc n      ≡⟨ cong (_% suc n) (sym (Data.Nat.Properties.+-identityʳ (toℕ t))) ⟩
  (toℕ t + 0) % suc n ∎
tick-iterate n t (suc k) = begin
  toℕ (run n k (tick n t))                 ≡⟨ tick-iterate n (tick n t) k ⟩
  (toℕ (tick n t) + k) % suc n             ≡⟨ cong (λ x → (x + k) % suc n) (toℕ-fromℕ< (m%n<n (suc (toℕ t)) (suc n))) ⟩
  ((suc (toℕ t) % suc n) + k) % suc n      ≡⟨ mod-add (suc (toℕ t)) k n ⟩
  (suc (toℕ t) + k) % suc n                ≡⟨ cong (_% suc n) (sym (+-suc (toℕ t) k)) ⟩
  (toℕ t + suc k) % suc n                  ∎

-- Eternal return: after n + 1 ticks every moment is itself again.
eternal-return : ∀ n (t : Moment n) → run n (suc n) t ≡ t
eternal-return n t = toℕ-injective (begin
  toℕ (run n (suc n) t)       ≡⟨ tick-iterate n t (suc n) ⟩
  (toℕ t + suc n) % suc n     ≡⟨ [m+n]%n≡m%n (toℕ t) (suc n) ⟩
  toℕ t % suc n               ≡⟨ self-mod n t ⟩
  toℕ t                       ∎)

-- The whole history repeats: the moment at time k + (n + 1) is the moment at time k.
history-periodic : ∀ n (t0 : Moment n) k → history n t0 (k + suc n) ≡ history n t0 k
history-periodic n t0 k = toℕ-injective (begin
  toℕ (run n (k + suc n) t0)        ≡⟨ tick-iterate n t0 (k + suc n) ⟩
  (toℕ t0 + (k + suc n)) % suc n    ≡⟨ cong (_% suc n) (sym (+-assoc (toℕ t0) k (suc n))) ⟩
  ((toℕ t0 + k) + suc n) % suc n    ≡⟨ [m+n]%n≡m%n (toℕ t0 + k) (suc n) ⟩
  (toℕ t0 + k) % suc n              ≡⟨ sym (tick-iterate n t0 k) ⟩
  toℕ (run n k t0)                  ∎)

-- Every moment comes back after every multiple of n + 1 ticks, so it comes back forever.
returns-forever : ∀ n (t : Moment n) m → run n (m * suc n) t ≡ t
returns-forever n t m = toℕ-injective (begin
  toℕ (run n (m * suc n) t)     ≡⟨ tick-iterate n t (m * suc n) ⟩
  (toℕ t + m * suc n) % suc n   ≡⟨ [m+kn]%n≡m%n (toℕ t) m (suc n) ⟩
  toℕ t % suc n                 ≡⟨ self-mod n t ⟩
  toℕ t                         ∎)
