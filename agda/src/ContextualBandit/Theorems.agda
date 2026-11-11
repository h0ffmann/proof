{-# OPTIONS --safe --without-K #-}

------------------------------------------------------------------------
-- What is proved, for every number of arms K (by induction on K)
--
-- 1. greedy, ucb and epsGreedy (for 0 ≤ ε ≤ 1) always return valid
--    probability distributions.
-- 2. ε-greedy explores: every arm gets probability at least ε / K, and the
--    greedy arm gets exactly 1 - ε + ε / K. With ε = 1 it is the uniform
--    decision of an A/B test.
-- 3. greedy and ucb pick a maximiser of their score, and ucb 0 is greedy.
-- 4. The UCB optimism lemma, the deterministic core of every UCB or LinUCB
--    regret proof: if the model is calibrated (each true mean lies within
--    β * width of the predicted mean), the arm that UCB picks loses at
--    most 2 * (β * width) against any arm. The regret bound then needs
--    (a) a probability bound for the calibration event and (b) a bound on
--    the sum of the widths; neither is here.
-- 5. The same lemma for greedy: if every estimate is within δ, greedy
--    loses at most 2 * δ.
-- 6. The agent depends on the history only through the model's belief.
--
-- The names are those of z3-scala/src/main/scala/bandit/domain/Theorems.scala,
-- which proves the same statements for K = 1 to MAX_ARMS only.
------------------------------------------------------------------------

module ContextualBandit.Theorems where

open import Data.Bool.Base using (if_then_else_; true; false)
open import Data.Fin.Base using (zero; suc)
open import Data.Fin.Properties using (_≟_)
open import Data.Nat.Base using (ℕ; zero; suc; NonZero)
open import Data.List.Base using (List)
open import Data.Product.Base using (_×_; _,_; proj₁; proj₂)
open import Data.Rational.Base
  using (ℚ; 0ℚ; 1ℚ; _+_; _*_; _-_; -_; _≤_; nonNegative; positive)
open import Data.Rational.Properties hiding (_≟_)
open import Data.Rational.Solver using (module +-*-Solver)
open import Function.Base using (_∘_)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst)
open import Relation.Nullary.Decidable.Core using (does; yes; no)

open import ContextualBandit.Interface
open import ContextualBandit.Argmax using (argmax-spec; argmax-cong)
open import ContextualBandit.Policies

open +-*-Solver using (solve; _:=_; _:+_; _:*_; _:-_; con)

private
  2ℚ : ℚ
  2ℚ = 1ℚ + 1ℚ

------------------------------------------------------------------------
-- Sums over the arms (mass is a fold over tabulate, so these go by
-- induction on K)

mass-cong : ∀ {K} {d e : Decision K} → (∀ a → d a ≡ e a) → mass d ≡ mass e
mass-cong {zero}  _   = refl
mass-cong {suc K} d≡e = cong₂ _+_ (d≡e zero) (mass-cong (d≡e ∘ suc))

mass-add : ∀ {K} (f g : Decision K) → mass (λ a → f a + g a) ≡ mass f + mass g
mass-add {zero}  f g = sym (+-identityˡ 0ℚ)
mass-add {suc K} f g =
  trans (cong (f zero + g zero +_) (mass-add (f ∘ suc) (g ∘ suc)))
        (interchange (f zero) (g zero) (mass (f ∘ suc)) (mass (g ∘ suc)))
  where
  interchange : ∀ a b c d → (a + b) + (c + d) ≡ (a + c) + (b + d)
  interchange = solve 4 (λ a b c d → (a :+ b) :+ (c :+ d) := (a :+ c) :+ (b :+ d)) refl

mass-mul : ∀ {K} (c : ℚ) (f : Decision K) → mass (λ a → c * f a) ≡ c * mass f
mass-mul {zero}  c f = sym (*-zeroʳ c)
mass-mul {suc K} c f =
  trans (cong (c * f zero +_) (mass-mul c (f ∘ suc)))
        (sym (*-distribˡ-+ c (f zero) (mass (f ∘ suc))))

mass-const : ∀ {K} (c : ℚ) → mass {K} (λ _ → c) ≡ ofℕ K * c
mass-const {zero}  c = sym (*-zeroˡ c)
mass-const {suc K} c =
  trans (cong₂ _+_ (sym (*-identityˡ c)) (mass-const {K} c))
        (sym (*-distribʳ-+ c 1ℚ (ofℕ K)))

mass-point : ∀ {K} (b : Arm K) → mass (point b) ≡ 1ℚ
mass-point {suc K} zero =
  trans (cong (1ℚ +_) (trans (mass-const {K} 0ℚ) (*-zeroʳ (ofℕ K)))) (+-identityʳ 1ℚ)
mass-point {suc K} (suc b) = trans (+-identityˡ _) (mass-point b)

invK-nonneg : ∀ K → 0ℚ ≤ invK K
invK-nonneg zero    = ≤-refl
invK-nonneg (suc K) =
  nonNegative⁻¹ (invK (suc K)) {{pos⇒nonNeg (invK (suc K)) {{1/pos⇒pos (ofℕ (suc K)) {{ofℕ-pos K}}}}}}

mass-uniform : ∀ K {{_ : NonZero K}} → mass (uniform K) ≡ 1ℚ
mass-uniform (suc K) =
  trans (mass-const {suc K} (invK (suc K)))
        (*-inverseʳ (ofℕ (suc K)) {{pos⇒nonZero (ofℕ (suc K)) {{ofℕ-pos K}}}})

mass-mix : ∀ {K} (w : ℚ) (d₁ d₂ : Decision K) →
           mass (mix w d₁ d₂) ≡ w * mass d₁ + (1ℚ - w) * mass d₂
mass-mix w d₁ d₂ =
  trans (mass-add (λ a → w * d₁ a) (λ a → (1ℚ - w) * d₂ a))
        (cong₂ _+_ (mass-mul w d₁) (mass-mul (1ℚ - w) d₂))

point-nonneg : ∀ {K} (b a : Arm K) → 0ℚ ≤ point b a
point-nonneg b a with does (a ≟ b)
... | true  = <⇒≤ 0<1
... | false = ≤-refl

point-valid : ∀ {K} (b : Arm K) → Valid (point b)
point-valid b = point-nonneg b , mass-point b

------------------------------------------------------------------------
-- Small facts about ℚ that the proofs below use

private
  0≤xy : ∀ {x y} → 0ℚ ≤ x → 0ℚ ≤ y → 0ℚ ≤ x * y
  0≤xy {x} {y} 0≤x 0≤y =
    nonNegative⁻¹ _ {{nonNeg*nonNeg⇒nonNeg x {{nonNegative 0≤x}} y {{nonNegative 0≤y}}}}

  0≤x+y : ∀ {x y} → 0ℚ ≤ x → 0ℚ ≤ y → 0ℚ ≤ x + y
  0≤x+y {x} {y} 0≤x 0≤y =
    nonNegative⁻¹ _ {{nonNeg+nonNeg⇒nonNeg x {{nonNegative 0≤x}} y {{nonNegative 0≤y}}}}

  0≤1-ε : ∀ {ε} → ε ≤ 1ℚ → 0ℚ ≤ 1ℚ - ε
  0≤1-ε {ε} ε≤1 =
    subst (_≤ 1ℚ - ε) (+-inverseʳ ε) (+-monoˡ-≤ (- ε) ε≤1)

  ≤y+x : ∀ {x y} → 0ℚ ≤ y → x ≤ y + x
  ≤y+x {x} {y} 0≤y = subst (_≤ y + x) (+-identityˡ x) (+-monoˡ-≤ x 0≤y)

  -- x + y = (x - y) + 2 * y
  split : ∀ x y → x + y ≡ (x - y) + 2ℚ * y
  split = solve 2 (λ x y → x :+ y := (x :- y) :+ (con 1ℚ :+ con 1ℚ) :* y) refl

------------------------------------------------------------------------
-- 1. Every rule returns a probability distribution

greedy-valid : ∀ {K} {{_ : NonZero K}} (est : Arm K → Estimate) → Valid (greedy est)
greedy-valid est = point-valid _

ucb-valid : ∀ {K} {{_ : NonZero K}} (β : ℚ) (est : Arm K → Estimate) → Valid (ucb β est)
ucb-valid β est = point-valid _

epsGreedy-valid : ∀ {K} {{_ : NonZero K}} (ε : ℚ) → 0ℚ ≤ ε → ε ≤ 1ℚ →
                  (est : Arm K → Estimate) → Valid (epsGreedy ε est)
epsGreedy-valid {K} ε 0≤ε ε≤1 est =
    (λ a → 0≤x+y (0≤xy 0≤ε (invK-nonneg K)) (0≤xy (0≤1-ε ε≤1) (point-nonneg _ a)))
  , trans (mass-mix ε (uniform K) (point (greedyArm est)))
          (trans (cong₂ (λ u p → ε * u + (1ℚ - ε) * p) (mass-uniform K) (mass-point (greedyArm est)))
                 (ε+1-ε ε))
  where
  ε+1-ε : ∀ e → e * 1ℚ + (1ℚ - e) * 1ℚ ≡ 1ℚ
  ε+1-ε = solve 1 (λ e → e :* con 1ℚ :+ (con 1ℚ :- e) :* con 1ℚ := con 1ℚ) refl

------------------------------------------------------------------------
-- 2. ε-greedy explores every arm

epsGreedy-prob : ∀ {K} {{_ : NonZero K}} (ε : ℚ) (est : Arm K → Estimate) (a : Arm K) →
  epsGreedy ε est a ≡
    (if does (a ≟ greedyArm est) then 1ℚ - ε + ε * invK K else ε * invK K)
epsGreedy-prob {K} ε est a with does (a ≟ greedyArm est)
... | true  = trans (cong (ε * invK K +_) (*-identityʳ (1ℚ - ε))) (+-comm (ε * invK K) (1ℚ - ε))
... | false = trans (cong (ε * invK K +_) (*-zeroʳ (1ℚ - ε))) (+-identityʳ (ε * invK K))

epsGreedy-explores : ∀ {K} {{_ : NonZero K}} (ε : ℚ) → ε ≤ 1ℚ →
  (est : Arm K → Estimate) (a : Arm K) → ε * invK K ≤ epsGreedy ε est a
epsGreedy-explores {K} ε ε≤1 est a
  rewrite epsGreedy-prob ε est a with does (a ≟ greedyArm est)
... | true  = ≤y+x (0≤1-ε ε≤1)
... | false = ≤-refl

-- With ε = 1, ε-greedy is the uniform decision: an A/B test.
epsGreedy-one-is-ab-test : ∀ {K} {{_ : NonZero K}} (est : Arm K → Estimate) (a : Arm K) →
  epsGreedy 1ℚ est a ≡ uniform K a
epsGreedy-one-is-ab-test {K} est a =
  trans (cong₂ _+_ (*-identityˡ (invK K)) (*-zeroˡ (point (greedyArm est) a)))
        (+-identityʳ (invK K))

------------------------------------------------------------------------
-- 3. Greedy and UCB pick maximisers

greedy-is-argmax : ∀ {K} {{_ : NonZero K}} (est : Arm K → Estimate) (a : Arm K) →
  mean (est a) ≤ mean (est (greedyArm est))
greedy-is-argmax est a = argmax-spec (λ a → mean (est a)) a

ucb-is-argmax : ∀ {K} {{_ : NonZero K}} (β : ℚ) (est : Arm K → Estimate) (a : Arm K) →
  ucbScore β (est a) ≤ ucbScore β (est (ucbArm β est))
ucb-is-argmax β est a = argmax-spec (λ a → ucbScore β (est a)) a

-- With β = 0, UCB is greedy (arm by arm: --safe has no function
-- extensionality).
ucb-zero : ∀ {K} {{_ : NonZero K}} (est : Arm K → Estimate) (a : Arm K) →
  ucb 0ℚ est a ≡ greedy est a
ucb-zero est a = cong (λ b → point b a)
  (argmax-cong _ _ (λ b → trans (cong (mean (est b) +_) (*-zeroˡ (width (est b))))
                                (+-identityʳ (mean (est b)))))

------------------------------------------------------------------------
-- 4. The UCB optimism lemma

-- The model is calibrated at scale β against the true mean rewards μ.
Calibrated : ∀ {K} → ℚ → (Arm K → ℚ) → (Arm K → Estimate) → Set
Calibrated β μ est = ∀ a →
  (mean (est a) - β * width (est a) ≤ μ a) ×
  (μ a ≤ mean (est a) + β * width (est a))

-- On the calibration event the arm that UCB picks is at most
-- 2 * (β * width) worse than any arm, the best one included. A sum of
-- this over the rounds is how the LinUCB regret bound is derived.
ucb-gap : ∀ {K} {{_ : NonZero K}} (β : ℚ) (μ : Arm K → ℚ) (est : Arm K → Estimate) →
  Calibrated β μ est → (a : Arm K) →
  μ a ≤ μ (ucbArm β est) + 2ℚ * (β * width (est (ucbArm β est)))
ucb-gap β μ est hcal a =
  ≤-trans (proj₂ (hcal a))
  (≤-trans (ucb-is-argmax β est a)
  (≤-trans (≤-reflexive (split m x))
           (+-monoˡ-≤ (2ℚ * x) (proj₁ (hcal (ucbArm β est))))))
  where
  m = mean (est (ucbArm β est))
  x = β * width (est (ucbArm β est))

------------------------------------------------------------------------
-- 5. Greedy with a δ-accurate model

greedy-gap : ∀ {K} {{_ : NonZero K}} (δ : ℚ) (μ : Arm K → ℚ) (est : Arm K → Estimate) →
  (∀ a → (mean (est a) - δ ≤ μ a) × (μ a ≤ mean (est a) + δ)) →
  (a : Arm K) → μ a ≤ μ (greedyArm est) + 2ℚ * δ
greedy-gap δ μ est hacc a =
  ≤-trans (proj₂ (hacc a))
  (≤-trans (+-monoˡ-≤ δ (greedy-is-argmax est a))
  (≤-trans (≤-reflexive (split (mean (est (greedyArm est))) δ))
           (+-monoˡ-≤ (2ℚ * δ) (proj₁ (hacc (greedyArm est))))))

------------------------------------------------------------------------
-- 6. The model is the only channel from history to decision

policy-factors : ∀ {C B : Set} {K : ℕ} (m : RewardModel C K B) (rule : DecisionRule K)
  (h₁ h₂ : List (Obs C K)) (c : C) →
  posterior m h₁ ≡ posterior m h₂ → (a : Arm K) →
  policy m rule h₁ c a ≡ policy m rule h₂ c a
policy-factors m rule h₁ h₂ c hpost a = cong (λ b → rule (estimate m b c) a) hpost
