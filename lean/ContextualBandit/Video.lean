import ContextualBandit.Theorems

/-!
# Invariants of the video script

The requirements of the owner for the 30-minute video (`papers/contextual-bandits/script/`),
as definitions and theorems. Each `R` is one sentence of the owner, 2026-11-09.

* **R1. The reward is the input of the user.** A `User` gives a reward in `[0, 1]` for
  each thing shown. The agent sees nothing else.
* **R2. Single-armed: exploitation = π(N), exploration = π(N+1).** One arm, two
  actions. `exploit` shows the current approximation again. `explore` spends one term.
* **R3. The A/B test is a special case of the CMAB.** The full A/B procedure, "explore
  then commit", is one decision rule: `epsGreedy 1` before the switch, `epsGreedy 0` after it.
* **R4. RSI is the same rule, applied to itself.** The arms of the outer agent are values
  of ε for the inner agent. The outer rule is `epsGreedy` again.
* **R5. The two series of π have positive terms.** Thus their partial sums increase.

The digits of π are measured in Haskell (`haskell/src/Pi.hs`). Core Lean has no real
numbers. This file has only what is exact over `Rat` and `Nat`.
-/

namespace CB.Video

open CB

/-! ## R1. The reward is the user's input -/

/-- A user. The user gives a reward in `[0, 1]` for each thing shown. -/
structure User (Shown : Type) where
  reward : Shown → Rat
  nonneg : ∀ s, 0 ≤ reward s
  le_one : ∀ s, reward s ≤ 1

theorem User.bounded {Shown : Type} (u : User Shown) (s : Shown) :
    0 ≤ u.reward s ∧ u.reward s ≤ 1 := ⟨u.nonneg s, u.le_one s⟩

/-! ## R2. Single-armed: exploitation shows π(N), exploration computes π(N+1) -/

inductive Action | exploit | explore
  deriving DecidableEq, Repr

/-- The state of the one-armed agent: the number of terms, the approximation it
shows, and the reward the user gave for it. -/
structure SA where
  n          : Nat
  shown      : Rat
  lastReward : Rat
  deriving Repr

/-- Exploration: compute the next approximation and show it to the user. Keep it if
the reward is not lower. `approx k` is the approximation with `k` terms. -/
def exploreStep (approx : Nat → Rat) (u : User Rat) (s : SA) : SA :=
  if s.lastReward ≤ u.reward (approx (s.n + 1))
    then ⟨s.n + 1, approx (s.n + 1), u.reward (approx (s.n + 1))⟩
    else ⟨s.n + 1, s.shown, s.lastReward⟩

/-- One step of the one-armed agent. -/
def step (approx : Nat → Rat) (u : User Rat) (s : SA) : Action → SA
  | .exploit => s
  | .explore => exploreStep approx u s

/-- Exploitation spends no term and changes nothing. The user sees π(N) again. -/
theorem step_exploit (approx : Nat → Rat) (u : User Rat) (s : SA) :
    step approx u s .exploit = s := rfl

/-- Exploration spends one term: from π(N) to π(N+1). -/
theorem step_explore_n (approx : Nat → Rat) (u : User Rat) (s : SA) :
    (step approx u s .explore).n = s.n + 1 := by
  simp only [step, exploreStep]; split <;> rfl

/-- After exploration, the reward of what the agent shows is not lower. -/
theorem step_explore_reward (approx : Nat → Rat) (u : User Rat) (s : SA) :
    s.lastReward ≤ (step approx u s .explore).lastReward := by
  simp only [step, exploreStep]; split
  · assumption
  · exact Rat.le_refl

/-- For each action, the recorded reward stays in `[0, 1]`, if it started there. -/
theorem step_reward_bounded (approx : Nat → Rat) (u : User Rat) (s : SA)
    (h : 0 ≤ s.lastReward ∧ s.lastReward ≤ 1) (a : Action) :
    0 ≤ (step approx u s a).lastReward ∧ (step approx u s a).lastReward ≤ 1 := by
  cases a with
  | exploit => exact h
  | explore =>
    simp only [step, exploreStep]; split
    · exact u.bounded _
    · exact h

/-! ## R3. The A/B test, whole, as one decision rule -/

/-- Explore-then-commit: uniform in the first `T` rounds, greedy after them. The
round `t` is the only extra input. The rule sees only the estimates. -/
def etc {K : Nat} [NeZero K] (T t : Nat) : DecisionRule K :=
  if t < T then epsGreedy 1 else epsGreedy 0

/-- With `ε = 0`, ε-greedy is greedy (the "commit" of the A/B test). -/
theorem epsGreedy_zero {K : Nat} [NeZero K] (est : Arm K → Estimate) :
    epsGreedy 0 est = greedy est := by
  funext a
  unfold epsGreedy mix greedy
  grind

/-- The test period of an A/B/n test is the uniform allocation. -/
theorem etc_before {K : Nat} [NeZero K] (T t : Nat) (h : t < T) (est : Arm K → Estimate) :
    etc T t est = uniform K := by
  unfold etc; rw [if_pos h]; exact epsGreedy_one_is_ab_test est

/-- After the test, all traffic goes to the arm with the best estimate. -/
theorem etc_after {K : Nat} [NeZero K] (T t : Nat) (h : ¬ t < T) (est : Arm K → Estimate) :
    etc T t est = greedy est := by
  unfold etc; rw [if_neg h]; exact epsGreedy_zero est

/-- Explore-then-commit is a valid distribution in every round. -/
theorem etc_valid {K : Nat} [NeZero K] (T t : Nat) (est : Arm K → Estimate) :
    (etc T t est).Valid := by
  unfold etc; split
  · exact epsGreedy_valid 1 (by decide) (by decide) est
  · exact epsGreedy_valid 0 (by decide) (by decide) est

/-! ## R4. RSI: the outer agent chooses the inner agent's ε with the same rule -/

/-- The outer bandit has `M` arms, one for each candidate `ε` of the inner bandit.
Its rule is `epsGreedy` again, with its own `ε₀`. -/
def outer {M : Nat} [NeZero M] (ε₀ : Rat) : DecisionRule M := epsGreedy ε₀

/-- The inner bandit, after the outer bandit selects arm `i`. -/
def inner {K M : Nat} [NeZero K] (εs : Arm M → Rat) (i : Arm M) : DecisionRule K :=
  epsGreedy (εs i)

/-- The two levels return distributions when each ε is a probability. -/
theorem rsi_valid {K M : Nat} [NeZero K] [NeZero M] (ε₀ : Rat) (h0 : 0 ≤ ε₀) (h1 : ε₀ ≤ 1)
    (εs : Arm M → Rat) (hs : ∀ i, 0 ≤ εs i ∧ εs i ≤ 1)
    (estOuter : Arm M → Estimate) (estInner : Arm K → Estimate) (i : Arm M) :
    (outer ε₀ estOuter).Valid ∧ (inner εs i estInner).Valid :=
  ⟨epsGreedy_valid ε₀ h0 h1 estOuter, epsGreedy_valid (εs i) (hs i).1 (hs i).2 estInner⟩

/-- The outer level continues to try each ε: each gets a probability of at least `ε₀ / M`. -/
theorem outer_explores {M : Nat} [NeZero M] (ε₀ : Rat) (h1 : ε₀ ≤ 1)
    (estOuter : Arm M → Estimate) (i : Arm M) :
    ε₀ * invK M ≤ outer ε₀ estOuter i :=
  epsGreedy_explores ε₀ h1 estOuter i

/-! ## R5. The two series of the simple example, as symbols

Core Lean has no real numbers, so π is not here. The terms and the partial sums are
exact rationals, and the invariants are about their shape:

* Leibniz (Gottfried Wilhelm Leibniz, 1674): `π/4 = 1 - 1/3 + 1/5 - ...`. Each pair of
  terms is positive. Thus the even partial sums increase.
* Ramanujan (Srinivasa Ramanujan, India, 1914; the owner calls him "the King of
  Mathematicians", 2026-11-09): `1/π = (2√2/9801) Σ (4k)! (1103 + 26390 k) / ((k!)^4 396^(4k))`.
  Each term is positive. Thus the partial sums increase, and the approximation of π
  decreases at each term.
* Gauss–Legendre (Carl Friedrich Gauss, "the prince of mathematicians") has square
  roots, which `Rat` does not have. It is in Haskell only.

The digits that each term gives are measured in Haskell (`haskell/src/Pi.hs`).
-/

/-- `a / y < a / x` when `0 < a` and `0 < x < y`. Core Lean has no lemma for this. -/
theorem div_lt_div_left_of_lt (a x y : Rat) (ha : 0 < a) (hx : 0 < x) (hxy : x < y) :
    a / y < a / x := by
  have hy : 0 < y := by grind
  rw [Rat.div_lt_iff hy]
  have h1 : a / x * x = a := Rat.div_mul_cancel (Rat.ne_of_gt hx)
  have h2 : 0 < a / x := by
    rw [Rat.div_def]; exact Rat.mul_pos ha (Rat.inv_pos.mpr hx)
  have h3 : 0 < a / x * (y - x) := Rat.mul_pos h2 (by grind)
  grind

/-- One pair of Leibniz terms, times 4: `4/(4k+1) - 4/(4k+3)`. -/
def leibnizPair (k : Nat) : Rat := 4 / (4 * k + 1) - 4 / (4 * k + 3)

/-- The even partial sums of Leibniz, as a sum of pairs. -/
def leibnizEven : Nat → Rat
  | 0 => 0
  | k + 1 => leibnizEven k + leibnizPair k

/-- Each pair is positive. -/
theorem leibnizPair_pos (k : Nat) : 0 < leibnizPair k := by
  unfold leibnizPair
  have hk : (0 : Rat) ≤ k := Rat.natCast_nonneg
  have h1 : (0 : Rat) < 4 * k + 1 := by grind
  have h := div_lt_div_left_of_lt 4 (4 * k + 1) (4 * k + 3) (by decide) h1 (by grind)
  grind

/-- **Invariant (Leibniz).** The even partial sums increase at every pair. -/
theorem leibnizEven_lt_succ (k : Nat) : leibnizEven k < leibnizEven (k + 1) := by
  simp only [leibnizEven]
  have := leibnizPair_pos k
  grind

/-- The factorial. Core Lean has none. -/
def fact : Nat → Nat
  | 0 => 1
  | n + 1 => (n + 1) * fact n

theorem fact_pos (n : Nat) : 0 < fact n := by
  induction n with
  | zero => decide
  | succ n ih => simp only [fact]; exact Nat.mul_pos (by omega) ih

/-- One term of Ramanujan's series, exact. -/
def ramTerm (k : Nat) : Rat :=
  ((fact (4 * k) * (1103 + 26390 * k) : Nat) : Rat) / ((fact k ^ 4 * 396 ^ (4 * k) : Nat) : Rat)

/-- The partial sums of Ramanujan's series. -/
def ramSum : Nat → Rat
  | 0 => 0
  | n + 1 => ramSum n + ramTerm n

/-- Each term is positive. -/
theorem ramTerm_pos (k : Nat) : 0 < ramTerm k := by
  unfold ramTerm
  have hn : 0 < fact (4 * k) * (1103 + 26390 * k) := Nat.mul_pos (fact_pos _) (by omega)
  have hd : 0 < fact k ^ 4 * 396 ^ (4 * k) :=
    Nat.mul_pos (Nat.pow_pos (fact_pos k)) (Nat.pow_pos (by decide))
  have hn' : (0 : Rat) < ((fact (4 * k) * (1103 + 26390 * k) : Nat) : Rat) := Rat.natCast_pos.mpr hn
  have hd' : (0 : Rat) < ((fact k ^ 4 * 396 ^ (4 * k) : Nat) : Rat) := Rat.natCast_pos.mpr hd
  rw [Rat.div_def]; exact Rat.mul_pos hn' (Rat.inv_pos.mpr hd')

/-- **Invariant (Ramanujan).** The partial sums increase at every term. -/
theorem ramSum_lt_succ (n : Nat) : ramSum n < ramSum (n + 1) := by
  simp only [ramSum]
  have := ramTerm_pos n
  grind

/-- With `c > 0` and `0 < S_n`, the approximation `1 / (c · S_n)` decreases at each
term. The approximation of Ramanujan comes down to π from above. -/
theorem ramApprox_anti (c : Rat) (hc : 0 < c) (n : Nat) (hn : 0 < ramSum n) :
    1 / (c * ramSum (n + 1)) < 1 / (c * ramSum n) := by
  have h := ramSum_lt_succ n
  have h0 : 0 < c * ramSum n := Rat.mul_pos hc hn
  have h2 : c * ramSum n < c * ramSum (n + 1) := by
    have := Rat.mul_pos hc (show 0 < ramSum (n + 1) - ramSum n by grind); grind
  exact div_lt_div_left_of_lt 1 _ _ (by decide) h0 h2

#eval ramSum 1    -- 1103
#eval leibnizEven 2  -- 4 - 4/3 + 4/5 - 4/7 = 304/105

/-! ## Examples. The `#eval` outputs are the reference for the Haskell `Video.hs`. -/

/-- `x` clipped to `[0, 1]`. -/
def clip (x : Rat) : Rat := if x < 0 then 0 else if 1 < x then 1 else x

theorem clip_nonneg (x : Rat) : 0 ≤ clip x := by
  unfold clip; split
  · exact Rat.le_refl
  · split
    · decide
    · grind

theorem clip_le_one (x : Rat) : clip x ≤ 1 := by
  unfold clip; split
  · decide
  · split
    · exact Rat.le_refl
    · grind

/-- Distance between two rationals, without `abs`. -/
def dist (a b : Rat) : Rat := if a ≤ b then b - a else a - b

/-- A user who gives a grade by the distance to a target: `1 - dist`, clipped to `[0, 1]`. -/
def byDistance (target : Rat) : User Rat where
  reward s := clip (1 - dist s target)
  nonneg _ := clip_nonneg _
  le_one _ := clip_le_one _

/-- Leibniz partial sums over `Rat`, exact: `4 · Σ_{k<n} (-1)^k / (2k+1)`. -/
def leibniz : Nat → Rat
  | 0 => 0
  | n + 1 => leibniz n + 4 * ((-1 : Rat) ^ n / (2 * n + 1))

#eval leibniz 1   -- 4
#eval leibniz 2   -- 8/3
#eval leibniz 5   -- 1052/315

#eval (step leibniz (byDistance (355/113)) ⟨1, leibniz 1, 0⟩ .explore).n  -- 2
#eval (step leibniz (byDistance (355/113)) ⟨1, leibniz 1, 0⟩ .exploit).n  -- 1

def est3 : Arm 3 → Estimate := fun a => ⟨[1/2, 9/10, 1/10][a.val]!, 0⟩
#eval (List.finRange 3).map (etc 10 3 est3)   -- [1/3, 1/3, 1/3]
#eval (List.finRange 3).map (etc 10 10 est3)  -- [0, 1, 0]

end CB.Video
