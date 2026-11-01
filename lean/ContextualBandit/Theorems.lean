import ContextualBandit.Policies

/-!
# What we prove

1. `greedy`, `ucb` and `epsGreedy` (for `0 ≤ ε ≤ 1`) always return valid
   probability distributions.
2. ε-greedy explores: every arm gets probability at least `ε / K`, and the
   greedy arm gets exactly `1 - ε + ε / K`.
3. `greedy` and `ucb` really pick a maximiser of their score.
4. **The UCB optimism lemma**, the deterministic core of every UCB or LinUCB
   regret proof. If the model is *calibrated* (each true mean lies within
   `β * width` of the predicted mean), then the arm UCB picks loses at most
   `2 β * width` against the best arm. The regret bound then needs only
   (a) a probability bound for the calibration event, and (b) a bound on the
   sum of the widths. Those are the probabilistic parts that need Mathlib.
5. The same lemma for greedy: if every estimate is within `δ`, greedy loses at
   most `2 δ`.
6. The agent depends on the history *only through the model's belief*.
-/

namespace CB

/-! ## List-sum helpers (core has no `Finset.sum`, so we roll our own) -/

theorem sum_map_add {α : Type} (f g : α → Rat) :
    ∀ l : List α, (l.map fun a => f a + g a).sum = (l.map f).sum + (l.map g).sum
  | [] => by simp only [List.map_nil, List.sum_nil]; grind
  | a :: as => by simp [sum_map_add f g as]; grind

theorem sum_map_mul {α : Type} (c : Rat) (f : α → Rat) :
    ∀ l : List α, (l.map fun a => c * f a).sum = c * (l.map f).sum
  | [] => by simp
  | a :: as => by simp [sum_map_mul c f as]; grind

theorem sum_map_const {α : Type} (c : Rat) :
    ∀ l : List α, (l.map fun _ => c).sum = l.length * c
  | [] => by simp
  | a :: as => by simp [sum_map_const c as]; grind

theorem mass_point : ∀ {K : Nat} (b : Arm K), mass (point b) = 1
  | 0, b => b.elim0
  | n + 1, b => by
    unfold mass
    rw [List.finRange_succ, List.map_cons, List.sum_cons, List.map_map]
    rcases Fin.eq_zero_or_eq_succ b with rfl | ⟨b', rfl⟩
    · have : (point (0 : Fin (n + 1)) ∘ Fin.succ) = fun _ => (0 : Rat) := by
        funext a; simp [point, Fin.succ_ne_zero]
      rw [this, sum_map_const]; simp [point]; grind
    · have : (point b'.succ ∘ Fin.succ) = point b' := by
        funext a; simp [point, Fin.succ_inj]
      rw [this]
      have ih := mass_point b'
      unfold mass at ih
      rw [ih]; simp [point, (Fin.succ_ne_zero b').symm]; grind

theorem invK_nonneg (K : Nat) : 0 ≤ invK K := by
  unfold invK
  rcases Nat.eq_zero_or_pos K with rfl | hK
  · simp; exact Rat.le_refl
  · have : (0 : Rat) < K := by
      have := (Rat.natCast_nonneg (a := K)); have : (K : Rat) ≠ 0 := by
        exact_mod_cast Nat.pos_iff_ne_zero.mp hK
      grind
    exact Rat.le_of_lt (Rat.inv_pos.mpr this)

theorem mass_uniform (K : Nat) [NeZero K] : mass (uniform K) = 1 := by
  unfold mass uniform invK
  rw [sum_map_const, List.length_finRange]
  have : (K : Rat) ≠ 0 := by exact_mod_cast NeZero.ne K
  exact Rat.mul_inv_cancel _ this

theorem mass_mix {K : Nat} (w : Rat) (d₁ d₂ : Decision K) :
    mass (mix w d₁ d₂) = w * mass d₁ + (1 - w) * mass d₂ := by
  unfold mass mix
  rw [sum_map_add, sum_map_mul, sum_map_mul]

theorem point_valid {K : Nat} (b : Arm K) : (point b).Valid :=
  ⟨fun a => by unfold point; split <;> grind, mass_point b⟩

/-! ## 1. Every rule returns a probability distribution -/

theorem greedy_valid {K : Nat} [NeZero K] (est : Arm K → Estimate) :
    (greedy est).Valid := point_valid _

theorem ucb_valid {K : Nat} [NeZero K] (β : Rat) (est : Arm K → Estimate) :
    (ucb β est).Valid := point_valid _

theorem epsGreedy_valid {K : Nat} [NeZero K] (ε : Rat) (h0 : 0 ≤ ε) (h1 : ε ≤ 1)
    (est : Arm K → Estimate) : (epsGreedy ε est).Valid := by
  refine ⟨fun a => ?_, ?_⟩
  · have hu := invK_nonneg K
    have hp := (point_valid (greedyArm est)).1 a
    unfold epsGreedy mix uniform
    have : 0 ≤ ε * invK K := Rat.mul_nonneg h0 hu
    have : 0 ≤ (1 - ε) * point (greedyArm est) a := Rat.mul_nonneg (by grind) hp
    grind
  · unfold epsGreedy
    rw [mass_mix, mass_uniform, mass_point]; grind

/-! ## 2. ε-greedy explores every arm -/

theorem epsGreedy_prob {K : Nat} [NeZero K] (ε : Rat) (est : Arm K → Estimate)
    (a : Arm K) :
    epsGreedy ε est a =
      if a = greedyArm est then 1 - ε + ε * invK K else ε * invK K := by
  unfold epsGreedy mix uniform point
  split <;> grind

theorem epsGreedy_explores {K : Nat} [NeZero K] (ε : Rat) (h1 : ε ≤ 1)
    (est : Arm K → Estimate) (a : Arm K) :
    ε * invK K ≤ epsGreedy ε est a := by
  rw [epsGreedy_prob]; split <;> grind

/-! ## 3. Greedy and UCB pick maximisers -/

theorem greedy_is_argmax {K : Nat} [NeZero K] (est : Arm K → Estimate) (a : Arm K) :
    (est a).mean ≤ (est (greedyArm est)).mean :=
  argmax_spec (fun a => (est a).mean) a

theorem ucb_is_argmax {K : Nat} [NeZero K] (β : Rat) (est : Arm K → Estimate)
    (a : Arm K) : ucbScore β (est a) ≤ ucbScore β (est (ucbArm β est)) :=
  argmax_spec (fun a => ucbScore β (est a)) a

/-- With `β = 0`, UCB is greedy. -/
theorem ucb_zero {K : Nat} [NeZero K] (est : Arm K → Estimate) :
    ucb 0 est = greedy est := by
  simp only [ucb, greedy, ucbArm, greedyArm, ucbScore, Rat.zero_mul, Rat.add_zero]

/-! ## 4. The UCB optimism lemma -/

/-- The model is calibrated at scale `β` against the true mean rewards `μ`. -/
def Calibrated {K : Nat} (β : Rat) (μ : Arm K → Rat) (est : Arm K → Estimate) : Prop :=
  ∀ a, (est a).mean - β * (est a).width ≤ μ a ∧ μ a ≤ (est a).mean + β * (est a).width

/-- **Optimism lemma.** On the calibration event, the arm chosen by UCB is at
most `2 β * width` worse than *any* arm, in particular the best one.
Summing this over rounds is exactly how LinUCB's regret bound is derived. -/
theorem ucb_gap {K : Nat} [NeZero K] (β : Rat) (μ : Arm K → Rat)
    (est : Arm K → Estimate) (hcal : Calibrated β μ est) (a : Arm K) :
    μ a ≤ μ (ucbArm β est) + 2 * (β * (est (ucbArm β est)).width) := by
  have h1 := (hcal a).2
  have h2 := ucb_is_argmax β est a
  have h3 := (hcal (ucbArm β est)).1
  unfold ucbScore at h2
  grind

/-! ## 5. Greedy with a δ-accurate model -/

theorem greedy_gap {K : Nat} [NeZero K] (δ : Rat) (μ : Arm K → Rat)
    (est : Arm K → Estimate)
    (hacc : ∀ a, (est a).mean - δ ≤ μ a ∧ μ a ≤ (est a).mean + δ) (a : Arm K) :
    μ a ≤ μ (greedyArm est) + 2 * δ := by
  have h1 := (hacc a).2
  have h2 := greedy_is_argmax est a
  have h3 := (hacc (greedyArm est)).1
  grind

/-! ## 6. The model is the only channel from history to decision -/

theorem policy_factors {C B : Type} {K : Nat} (m : RewardModel C K B)
    (rule : DecisionRule K) (h₁ h₂ : List (Obs C K)) (c : C)
    (hpost : m.posterior h₁ = m.posterior h₂) :
    policy m rule h₁ c = policy m rule h₂ c := by
  simp [policy, hpost]

end CB
