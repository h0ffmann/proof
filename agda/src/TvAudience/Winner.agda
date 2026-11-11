{-# OPTIONS --safe --without-K #-}

-- The slot winner of `tv-audience/python/experiment.py`: the channel with the largest audience in
-- a slot (`groupby("sid").idxmax()`, which keeps the first maximum), and the winner accuracy, the
-- share of slots where the forecasts name the channel the actuals name.
--
-- The theorems: the winner does not change when every forecast of the slot is multiplied by the
-- same c > 0; so the JCS winner is the channel with the largest weight exp(u), whatever the pool
-- forecast; the accuracy is between 0 and 1, and it is 1 for perfect forecasts.
module TvAudience.Winner where

open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.List using (List; []; _∷_; map)
open import Data.Nat as ℕ using (ℕ; zero; suc; _≡ᵇ_)
open import Data.Nat.Properties using (≡⇒≡ᵇ)
open import Data.Product using (_×_; _,_)
open import Data.Rational
  using (ℚ; 0ℚ; 1ℚ; _+_; _*_; _≤_; _<_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; +-mono-≤; *-monoʳ-<-pos; *-cancelˡ-<-nonNeg; _<?_; _≤?_; <⇒≤)
open import Data.Rational.Base using (positive; nonNegative)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:*_; con)
open import Relation.Nullary using (does; Dec; yes; no)
open import Relation.Nullary.Decidable using (dec-true; dec-false; from-yes)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst)

open import FatTails.Sample using (size; size-nonneg; inv₀; _/₀_; +-nonneg; *-nonneg; inv₀-pos)
open import OceanWaves.Order using (div-le-of-le-mul)
open import TvAudience.Jcs using (jcsShare; jcsForecast; denom; denom-pos; NonNeg)

-- The running argmax: the best index so far changes only on a strictly larger value.
go : ℕ → ℕ → ℚ → List ℚ → ℕ
go i b v []       = b
go i b v (x ∷ xs) = if does (v <? x) then go (suc i) i x xs else go (suc i) b v xs

-- The index of the first largest value; 0 for an empty slot.
winner : List ℚ → ℕ
winner []       = 0
winner (x ∷ xs) = go 1 0 x xs

-- ---------------------------------------------------------------------------------------------

private
  *-pos-mono-does : ∀ {c} v x → 0ℚ < c → does (c * v <? c * x) ≡ does (v <? x)
  *-pos-mono-does {c} v x hc = case (v <? x)
    where
    case : Dec (v < x) → does (c * v <? c * x) ≡ does (v <? x)
    case (yes p) = trans (dec-true (c * v <? c * x) (*-monoʳ-<-pos c {{positive hc}} p))
                         (sym (dec-true (v <? x) p))
    case (no ¬p) = trans (dec-false (c * v <? c * x) (λ q → ¬p (*-cancelˡ-<-nonNeg c {{nonNegative (<⇒≤ hc)}} q)))
                         (sym (dec-false (v <? x) ¬p))

go-scale : ∀ {c} i b v xs → 0ℚ < c → go i b (c * v) (map (c *_) xs) ≡ go i b v xs
go-scale         i b v []       hc = refl
go-scale {c} i b v (x ∷ xs) hc =
  trans (cong (λ t → if t then go (suc i) i (c * x) (map (c *_) xs) else go (suc i) b (c * v) (map (c *_) xs))
              (*-pos-mono-does v x hc))
        (cong₂ (λ p q → if does (v <? x) then p else q) (go-scale (suc i) i x xs hc) (go-scale (suc i) b v xs hc))

-- Scaling every forecast of a slot by c > 0 keeps its winner.
winner-scale : ∀ {c} xs → 0ℚ < c → winner (map (c *_) xs) ≡ winner xs
winner-scale []       hc = refl
winner-scale (x ∷ xs) hc = go-scale 1 0 x xs hc

-- The JCS winner is the channel with the largest weight, for any pool forecast above 0.
jcs-winner : ∀ pool ws → 0ℚ < pool → NonNeg ws → winner (jcsForecast pool ws) ≡ winner ws
jcs-winner pool ws hp h =
  trans (cong winner (as-scale ws)) (winner-scale ws (*-pos′ hp (inv₀-pos (denom-pos ws h))))
  where
  k = pool * inv₀ (denom ws)
  as-scale : ∀ vs → map (λ w → pool * jcsShare ws w) vs ≡ map (k *_) vs
  as-scale []       = refl
  as-scale (v ∷ vs) =
    cong₂ _∷_ (solve 3 (λ p x i → p :* (x :* i) := (p :* i) :* x) refl pool v (inv₀ (denom ws))) (as-scale vs)
  open import OceanWaves.Order using () renaming (*-pos to *-pos′)

-- ---------------------------------------------------------------------------------------------
-- Accuracy

-- One slot: the winner of the actuals and the winner of the forecasts.
hit : ℕ × ℕ → ℚ
hit (a , f) = if a ≡ᵇ f then 1ℚ else 0ℚ

hits : List (ℕ × ℕ) → ℚ
hits []       = 0ℚ
hits (p ∷ ps) = hit p + hits ps

accuracy : List (ℕ × ℕ) → ℚ
accuracy ps = hits ps /₀ size ps

private
  hit-le-one : ∀ p → 0ℚ ≤ hit p × hit p ≤ 1ℚ
  hit-le-one (a , f) with a ≡ᵇ f
  ... | true  = from-yes (0ℚ ≤? 1ℚ) , ≤-refl
  ... | false = ≤-refl , from-yes (0ℚ ≤? 1ℚ)

  hits-between : ∀ ps → 0ℚ ≤ hits ps × hits ps ≤ size ps
  hits-between []       = ≤-refl , ≤-refl
  hits-between (p ∷ ps) with hit-le-one p | hits-between ps
  ... | h0 , h1 | s0 , s1 = +-nonneg h0 s0 , subst (hit p + hits ps ≤_) refl (+-mono-≤ h1 s1)

accuracy-nonneg : ∀ ps → 0ℚ ≤ accuracy ps
accuracy-nonneg ps with hits-between ps
... | h0 , _ = *-nonneg h0 (OceanWaves.Order.inv₀-nonneg (size-nonneg ps))
  where import OceanWaves.Order

accuracy-le-one : ∀ p ps → accuracy (p ∷ ps) ≤ 1ℚ
accuracy-le-one p ps with hits-between (p ∷ ps)
... | _ , h1 = div-le-of-le-mul (size-pos p ps) (subst (hits (p ∷ ps) ≤_) (sym (solve 1 (λ n → con 1ℚ :* n := n) refl (size (p ∷ ps)))) h1)
  where open import FatTails.Sample using () renaming (size-cons-pos to size-pos)

-- Perfect forecasts name every winner.
perfectSlots : List ℕ → List (ℕ × ℕ)
perfectSlots = map (λ a → (a , a))

hits-perfect : ∀ as → hits (perfectSlots as) ≡ size as
hits-perfect []       = refl
hits-perfect (a ∷ as) = cong₂ _+_ (one a) (hits-perfect as)
  where
  one : ∀ a → hit (a , a) ≡ 1ℚ
  one a with a ≡ᵇ a in eq
  ... | true  = refl
  ... | false = Data.Empty.⊥-elim (subst Data.Bool.T eq (≡⇒≡ᵇ a a refl))
    where import Data.Empty; import Data.Bool

accuracy-perfect : ∀ a as → accuracy (perfectSlots (a ∷ as)) ≡ 1ℚ
accuracy-perfect a as =
  trans (cong (_/₀ size (perfectSlots (a ∷ as))) (hits-perfect (a ∷ as)))
    (trans (cong (λ n → size (a ∷ as) /₀ n) (size-map′ (λ x → (x , x)) (a ∷ as)))
      (inv₀-inverse′ (size (a ∷ as)) (<⇒≢0′ (size-cons-pos′ a as))))
  where
  open import FatTails.Sample using ()
    renaming (size-map to size-map′; inv₀-inverse to inv₀-inverse′; <⇒≢0 to <⇒≢0′; size-cons-pos to size-cons-pos′)
