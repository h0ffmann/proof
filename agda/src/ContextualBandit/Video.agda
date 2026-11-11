{-# OPTIONS --safe --without-K #-}

------------------------------------------------------------------------
-- The invariants of the video script, R1 to R5
--
-- Ported from z3-scala/src/main/scala/bandit/domain/Video.scala (`z3-scala/z3.sh video`). The
-- names follow Z3, with `-` for `_`. haskell/src/Video.hs is the port that runs.
--
-- * R1. The reward is the input of the user, in [0, 1]: `clip`, `byDistance`.
-- * R2. One arm, two actions: to exploit keeps the state, to explore pays one term of the
--   series, shows pi(n+1) and keeps the new grade when it is not lower.
-- * R3. Explore-then-commit is one decision rule: epsGreedy 1 before the horizon, epsGreedy 0
--   after it.
-- * R4. RSI: the outer agent picks a value of eps for the inner agent with epsGreedy again.
-- * R5. The two series of pi have positive terms, so their partial sums increase.
--
-- Z3 checks R3 and R4 for K = 3 inner and M = 4 outer arms. Agda proves them for every K and
-- M. Z3 has no factorial of a symbolic k, so it checks the Ramanujan terms for k = 0 to 9.
-- Agda proves that every term is positive and that every partial sum is less than the next.
-- Z3 proves the Leibniz pair positive for every real k ≥ 0; Agda for every rational k ≥ 0, and
-- it derives that the paired partial sums increase. The examples at the end are the ground
-- truth of the Haskell spec check, checked by `refl`.
------------------------------------------------------------------------

module ContextualBandit.Video where

open import Data.Fin.Base using (zero; suc)
open import Data.Integer.Base using (+_; -_)
open import Data.List.Base using (List; []; _∷_; tabulate)
open import Data.Nat.Base as ℕ using (ℕ; zero; suc; NonZero; _!; _^_)
open import Data.Nat.Properties using (_!≢0; m*n≢0; m^n≢0)
open import Data.Product.Base using (_×_; _,_)
open import Data.Rational.Base
  using (ℚ; 0ℚ; 1ℚ; _+_; _*_; _-_; _/_; _≤_; _<_; normalize; Positive; positive)
open import Data.Rational.Properties
  using (_≤?_; _<?_; ≤-refl; ≤-trans; <⇒≤; ≮⇒≥; <⇒≢; positive⁻¹; normalize-pos;
         *-monoʳ-<-pos; +-monoʳ-<; +-identityʳ; <-≤-trans)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong; subst)
open import Data.Empty using (⊥)
open import Relation.Nullary using (Dec; yes; no; ¬_; contradiction)
open import Relation.Nullary.Decidable using (from-yes)

open import ContextualBandit.Interface
open import ContextualBandit.Policies
open import ContextualBandit.Theorems
  using (epsGreedy-valid; epsGreedy-explores; epsGreedy-one-is-ab-test)
open import OceanWaves.Order
  using (_/₀_; inv₀; inv₀-inverse; inv₀-pos; div-pos; by-diff<; <⇒0<-; *-pos; +-pos; lit)

0≤1 : 0ℚ ≤ 1ℚ
0≤1 = from-yes (0ℚ ≤? 1ℚ)

------------------------------------------------------------------------
-- R1. The reward is the input of the user, in [0, 1]

-- v brought into [0, 1]: Z3's ite(v < 0, 0, ite(1 < v, 1, v)), as a function of the answers.
clipD : (v : ℚ) → Dec (v < 0ℚ) → Dec (1ℚ < v) → ℚ
clipD v (yes _) _       = 0ℚ
clipD v (no _)  (yes _) = 1ℚ
clipD v (no _)  (no _)  = v

clip : ℚ → ℚ
clip v = clipD v (v <? 0ℚ) (1ℚ <? v)

distD : (a b : ℚ) → Dec (a ≤ b) → ℚ
distD a b (yes _) = b - a
distD a b (no _)  = a - b

dist : ℚ → ℚ → ℚ
dist a b = distD a b (a ≤? b)

-- The simulated user of the video: the grade of v is 1 - |v - t|, clipped.
byDistance : ℚ → ℚ → ℚ
byDistance t v = clip (1ℚ - dist v t)

clipD-nonneg : ∀ v d₁ d₂ → 0ℚ ≤ clipD v d₁ d₂
clipD-nonneg v (yes _)  _       = ≤-refl
clipD-nonneg v (no _)   (yes _) = 0≤1
clipD-nonneg v (no v≮0) (no _)  = ≮⇒≥ v≮0

clipD-le-one : ∀ v d₁ d₂ → clipD v d₁ d₂ ≤ 1ℚ
clipD-le-one v (yes _) _        = 0≤1
clipD-le-one v (no _)  (yes _)  = ≤-refl
clipD-le-one v (no _)  (no 1≮v) = ≮⇒≥ 1≮v

clip-nonneg : ∀ x → 0ℚ ≤ clip x
clip-nonneg x = clipD-nonneg x (x <? 0ℚ) (1ℚ <? x)

clip-le-one : ∀ x → clip x ≤ 1ℚ
clip-le-one x = clipD-le-one x (x <? 0ℚ) (1ℚ <? x)

-- User.bounded: every grade of the simulated user is in [0, 1], for every target and value.
byDistance-bounded : ∀ t x → 0ℚ ≤ byDistance t x × byDistance t x ≤ 1ℚ
byDistance-bounded t x = clip-nonneg (1ℚ - dist x t) , clip-le-one (1ℚ - dist x t)

------------------------------------------------------------------------
-- R2. One arm. The state is (n, shown, lastReward): the terms paid for, the approximation the
-- user saw, the grade the user gave. approxNext is pi(n+1) and rewardNext the user's grade of
-- it.

record State : Set where
  constructor ⟨_,_,_⟩
  field
    n          : ℚ
    shown      : ℚ
    lastReward : ℚ

open State public

-- To exploit changes nothing.
exploit : State → State
exploit s = s

-- To explore pays one term, shows pi(n+1), and keeps the new grade when it is not lower.
exploreD : (approxNext rewardNext : ℚ) (s : State) → Dec (lastReward s ≤ rewardNext) → State
exploreD a r ⟨ k , v , l ⟩ (yes _) = ⟨ k + 1ℚ , a , r ⟩
exploreD a r ⟨ k , v , l ⟩ (no _)  = ⟨ k + 1ℚ , v , l ⟩

explore : (approxNext rewardNext : ℚ) → State → State
explore a r s = exploreD a r s (lastReward s ≤? r)

step-exploit : ∀ s → n (exploit s) ≡ n s × shown (exploit s) ≡ shown s ×
                     lastReward (exploit s) ≡ lastReward s
step-exploit s = refl , refl , refl

step-explore-n : ∀ a r s → n (explore a r s) ≡ n s + 1ℚ
step-explore-n a r s = go (lastReward s ≤? r)
  where
  go : ∀ d → n (exploreD a r s d) ≡ n s + 1ℚ
  go (yes _) = refl
  go (no _)  = refl

step-explore-reward : ∀ a r s → lastReward s ≤ lastReward (explore a r s)
step-explore-reward a r s = go (lastReward s ≤? r)
  where
  go : ∀ d → lastReward s ≤ lastReward (exploreD a r s d)
  go (yes l≤r) = l≤r
  go (no _)    = ≤-refl

-- With a bounded user and a grade in [0, 1], both actions keep the grade in [0, 1].
step-reward-bounded : ∀ a r s → 0ℚ ≤ r → r ≤ 1ℚ → 0ℚ ≤ lastReward s → lastReward s ≤ 1ℚ →
  (0ℚ ≤ lastReward (explore a r s) × lastReward (explore a r s) ≤ 1ℚ) ×
  (0ℚ ≤ lastReward (exploit s) × lastReward (exploit s) ≤ 1ℚ)
step-reward-bounded a r s 0≤r r≤1 0≤l l≤1 = go (lastReward s ≤? r) , (0≤l , l≤1)
  where
  go : ∀ d → 0ℚ ≤ lastReward (exploreD a r s d) × lastReward (exploreD a r s d) ≤ 1ℚ
  go (yes _) = 0≤r , r≤1
  go (no _)  = 0≤l , l≤1

------------------------------------------------------------------------
-- R3. Explore-then-commit is one decision rule

module _ {K : ℕ} {{_ : NonZero K}} where

  -- Z3 builds etc arm by arm with ite(now < horizon, ·, ·); it is the same decision.
  etcD : {horizon now : ℚ} → Dec (now < horizon) → DecisionRule K
  etcD (yes _) est = epsGreedy 1ℚ est
  etcD (no _)  est = epsGreedy 0ℚ est

  etc : (horizon now : ℚ) → DecisionRule K
  etc horizon now = etcD (now <? horizon)

  epsGreedy-zero : ∀ (est : Arm K → Estimate) (a : Arm K) → epsGreedy 0ℚ est a ≡ greedy est a
  epsGreedy-zero est a =
    solve 2 (λ u p → con 0ℚ :* u :+ (con 1ℚ :- con 0ℚ) :* p := p) refl
      (invK K) (point (greedyArm est) a)

  etc-before : ∀ horizon now (est : Arm K → Estimate) (a : Arm K) → now < horizon → etc horizon now est a ≡ uniform K a
  etc-before horizon now est a lt = go (now <? horizon)
    where
    go : (d : Dec (now < horizon)) → etcD d est a ≡ uniform K a
    go (yes _)  = epsGreedy-one-is-ab-test est a
    go (no ¬lt) = contradiction lt ¬lt

  etc-after : ∀ horizon now (est : Arm K → Estimate) (a : Arm K) → ¬ now < horizon → etc horizon now est a ≡ greedy est a
  etc-after horizon now est a ge = go (now <? horizon)
    where
    go : (d : Dec (now < horizon)) → etcD d est a ≡ greedy est a
    go (yes lt) = contradiction lt ge
    go (no _)   = epsGreedy-zero est a

  etc-valid : ∀ horizon now (est : Arm K → Estimate) → Valid (etc horizon now est)
  etc-valid horizon now est = go (now <? horizon)
    where
    go : (d : Dec (now < horizon)) → Valid (etcD d est)
    go (yes _) = epsGreedy-valid 1ℚ 0≤1 ≤-refl est
    go (no _)  = epsGreedy-valid 0ℚ ≤-refl 0≤1 est

------------------------------------------------------------------------
-- R4. RSI: the outer agent (M arms, one per candidate eps) uses epsGreedy too

module _ {M K : ℕ} {{_ : NonZero M}} {{_ : NonZero K}} where

  -- The outer decision is valid for every eps0 in [0, 1].
  rsi-valid-outer : ∀ eps0 → 0ℚ ≤ eps0 → eps0 ≤ 1ℚ → (outerEst : Arm M → Estimate) →
    Valid (epsGreedy eps0 outerEst)
  rsi-valid-outer eps0 = epsGreedy-valid eps0

  -- Each inner decision is valid when its eps, the value of an outer arm, is in [0, 1].
  rsi-valid-inner : (innerEps : Arm M → ℚ) → (∀ i → 0ℚ ≤ innerEps i × innerEps i ≤ 1ℚ) →
    (innerEst : Arm K → Estimate) → ∀ i → Valid (epsGreedy (innerEps i) innerEst)
  rsi-valid-inner innerEps bounded innerEst i with bounded i
  ... | 0≤e , e≤1 = epsGreedy-valid (innerEps i) 0≤e e≤1 innerEst

  -- The outer agent tries every value of eps with probability at least eps0 / M.
  outer-explores : ∀ eps0 → eps0 ≤ 1ℚ → (outerEst : Arm M → Estimate) (i : Arm M) →
    eps0 * invK M ≤ epsGreedy eps0 outerEst i
  outer-explores eps0 = epsGreedy-explores eps0

------------------------------------------------------------------------
-- R5. The series of pi have positive terms

private
  ≢0 : ∀ {q} → 0ℚ < q → q ≡ 0ℚ → ⊥
  ≢0 0<q q≡0 = <⇒≢ 0<q (sym q≡0)

-- 1/x is strictly decreasing on the positive rationals.
inv₀-anti : ∀ {a b} → 0ℚ < a → a < b → inv₀ b < inv₀ a
inv₀-anti {a} {b} 0<a a<b =
  by-diff< ((b - a) * inv₀ a * inv₀ b) (sym diff)
    (*-pos (*-pos (<⇒0<- a<b) (inv₀-pos 0<a)) (inv₀-pos 0<b))
  where
  0<b = <-trans′ 0<a a<b
    where open import Data.Rational.Properties using () renaming (<-trans to <-trans′)
  ia = inv₀ a
  ib = inv₀ b
  diff : (b - a) * ia * ib ≡ ia - ib
  diff = trans (solve 4 (λ a b ia ib → (b :- a) :* ia :* ib := (b :* ib) :* ia :- (a :* ia) :* ib)
                       refl a b ia ib)
         (trans (cong₂′ (λ u v → u * ia - v * ib) (inv₀-inverse b (≢0 0<b)) (inv₀-inverse a (≢0 0<a)))
                (solve 2 (λ ia ib → con 1ℚ :* ia :- con 1ℚ :* ib := ia :- ib) refl ia ib))
    where open import Relation.Binary.PropositionalEquality using () renaming (cong₂ to cong₂′)

-- Two consecutive terms of Leibniz's series, times 4: 4/(4k+1) - 4/(4k+3).
leibnizPair : ℚ → ℚ
leibnizPair k = lit 4 /₀ (lit 4 * k + 1ℚ) - lit 4 /₀ (lit 4 * k + lit 3)

-- Z3: leibnizPair_pos (real k >= 0). Here for every rational k ≥ 0.
leibnizPair-pos : ∀ k → 0ℚ ≤ k → 0ℚ < leibnizPair k
leibnizPair-pos k 0≤k = <⇒0<- (*-monoʳ-<-pos (lit 4) {{positive 0<4}} (inv₀-anti 0<x x<y))
  where
  0<4 : 0ℚ < lit 4
  0<4 = from-yes (0ℚ <? lit 4)
  x = lit 4 * k + 1ℚ
  y = lit 4 * k + lit 3
  0<4k : 0ℚ ≤ lit 4 * k
  0<4k = *-nonneg′ (<⇒≤ 0<4) 0≤k
    where open import OceanWaves.Order using () renaming (*-nonneg to *-nonneg′)
  0<x : 0ℚ < x
  0<x = subst (0ℚ <_) (solve 1 (λ z → con 1ℚ :+ z := z :+ con 1ℚ) refl (lit 4 * k))
          (+-pos (from-yes (0ℚ <? 1ℚ)) 0<4k)
  x<y : x < y
  x<y = +-monoʳ-< (lit 4 * k) (from-yes (1ℚ <? lit 3))

-- 4 * sum over the first n pairs, the paired partial sums of Leibniz's series.
leibnizEven : ℕ → ℚ
leibnizEven zero    = 0ℚ
leibnizEven (suc j) = leibnizEven j + leibnizPair (lit j)

lit-nonneg : ∀ n → 0ℚ ≤ lit n
lit-nonneg zero    = ≤-refl
lit-nonneg (suc m) = <⇒≤ (positive⁻¹ (lit (suc m)) {{normalize-pos (suc m) 1}})

lit-pos : ∀ n → .{{NonZero n}} → 0ℚ < lit n
lit-pos (suc m) = positive⁻¹ (lit (suc m)) {{normalize-pos (suc m) 1}}

leibnizEven-lt-succ : ∀ j → leibnizEven j < leibnizEven (suc j)
leibnizEven-lt-succ j =
  subst (_< leibnizEven (suc j)) (+-identityʳ (leibnizEven j))
    (+-monoʳ-< (leibnizEven j) (leibnizPair-pos (lit j) (lit-nonneg j)))

-- 4 * sum_{j < terms} (-1)^j / (2j + 1).
leibniz : ℕ → ℚ
leibniz zero    = 0ℚ
leibniz (suc j) = leibniz j + term j
  where
  sign : ℕ → ℚ
  sign zero          = lit 4
  sign (suc zero)    = 0ℚ - lit 4
  sign (suc (suc i)) = sign i
  term : ℕ → ℚ
  term i = sign i /₀ lit (suc (i ℕ.+ i))

-- (4j)! (1103 + 26390 j) / ((j!)^4 396^(4j)), the j-th term of Ramanujan's sum.
ramanujanTerm : ℕ → ℚ
ramanujanTerm j =
  lit ((4 ℕ.* j) ! ℕ.* (1103 ℕ.+ 26390 ℕ.* j)) /₀ lit ((j !) ^ 4 ℕ.* 396 ^ (4 ℕ.* j))

-- Z3: ramTerm_pos (k = 0..9). Here for every j.
ramanujanTerm-pos : ∀ j → 0ℚ < ramanujanTerm j
ramanujanTerm-pos j =
  div-pos (lit-pos _ {{m*n≢0 ((4 ℕ.* j) !) (1103 ℕ.+ 26390 ℕ.* j) {{(4 ℕ.* j) !≢0}}}})
          (lit-pos _ {{m*n≢0 ((j !) ^ 4) (396 ^ (4 ℕ.* j))
                        {{m^n≢0 (j !) 4 {{j !≢0}}}} {{m^n≢0 396 (4 ℕ.* j)}}}})

ramSum : ℕ → ℚ
ramSum zero    = 0ℚ
ramSum (suc j) = ramSum j + ramanujanTerm j

-- Z3: ramSum_lt_succ (n = 0..9). Here for every n.
ramSum-lt-succ : ∀ n → ramSum n < ramSum (suc n)
ramSum-lt-succ n =
  subst (_< ramSum (suc n)) (+-identityʳ (ramSum n)) (+-monoʳ-< (ramSum n) (ramanujanTerm-pos n))

-- Ramanujan's approximation of pi is 1 / (c * s): a larger partial sum gives a smaller value.
ramApprox-anti : ∀ c s s′ → 0ℚ < c → 0ℚ < s → s < s′ → inv₀ (c * s′) < inv₀ (c * s)
ramApprox-anti c s s′ 0<c 0<s s<s′ =
  inv₀-anti (*-pos 0<c 0<s) (*-monoʳ-<-pos c {{positive 0<c}} s<s′)

------------------------------------------------------------------------
-- Examples: the ground truth of the Haskell spec check, by refl

leibniz-1 : leibniz 1 ≡ + 4 / 1
leibniz-1 = refl

leibniz-2 : leibniz 2 ≡ + 8 / 3
leibniz-2 = refl

leibniz-5 : leibniz 5 ≡ + 1052 / 315
leibniz-5 = refl

leibnizEven-2 : leibnizEven 2 ≡ + 304 / 105
leibnizEven-2 = refl

ramSum-1 : ramSum 1 ≡ + 1103 / 1
ramSum-1 = refl

est3 : Arm 3 → Estimate
est3 zero             = estimate⟨ + 1 / 2  , 0ℚ ⟩
est3 (suc zero)       = estimate⟨ + 9 / 10 , 0ℚ ⟩
est3 (suc (suc zero)) = estimate⟨ + 1 / 10 , 0ℚ ⟩

etc-10-3 : tabulate (etc (lit 10) (lit 3) est3) ≡ + 1 / 3 ∷ + 1 / 3 ∷ + 1 / 3 ∷ []
etc-10-3 = refl

etc-10-10 : tabulate (etc (lit 10) (lit 10) est3) ≡ 0ℚ ∷ 1ℚ ∷ 0ℚ ∷ []
etc-10-10 = refl

-- step with leibniz and byDistance (355/113), from (1, leibniz 1, 0): explore gives n = 2,
-- exploit n = 1.
start : State
start = ⟨ 1ℚ , leibniz 1 , 0ℚ ⟩

step-explore-example : n (explore (leibniz 2) (byDistance (+ 355 / 113) (leibniz 2)) start) ≡ + 2 / 1
step-explore-example = refl

step-exploit-example : n (exploit start) ≡ 1ℚ
step-exploit-example = refl
