import ContextualBandit.Interface

/-!
# Verified argmax

Every deterministic rule (greedy, UCB) is "argmax of some score". Here we
define argmax once and prove that it really is a maximiser. Ties go to the
earliest arm, which is the same convention as the Haskell port.
-/

namespace CB

/-- Left fold keeping the first element with the largest score. -/
def argmaxFrom {α : Type} (f : α → Rat) (best : α) : List α → α
  | [] => best
  | a :: as => argmaxFrom f (if f best < f a then a else best) as

theorem argmaxFrom_ge_start {α : Type} (f : α → Rat) :
    ∀ (l : List α) (best : α), f best ≤ f (argmaxFrom f best l)
  | [], best => by simp [argmaxFrom]; exact Rat.le_refl
  | a :: as, best => by
    simp only [argmaxFrom]
    have ih := argmaxFrom_ge_start f as (if f best < f a then a else best)
    split at ih <;> grind

theorem argmaxFrom_ge_mem {α : Type} (f : α → Rat) :
    ∀ (l : List α) (best x : α), x ∈ l → f x ≤ f (argmaxFrom f best l)
  | [], _, _, h => by simp at h
  | a :: as, best, x, h => by
    simp only [argmaxFrom]
    rcases List.mem_cons.mp h with rfl | h
    · have := argmaxFrom_ge_start f as (if f best < f x then x else best)
      split at this <;> grind
    · exact argmaxFrom_ge_mem f as _ x h

theorem argmaxFrom_mem {α : Type} (f : α → Rat) :
    ∀ (l : List α) (best : α), argmaxFrom f best l = best ∨ argmaxFrom f best l ∈ l
  | [], _ => by simp [argmaxFrom]
  | a :: as, best => by
    simp only [argmaxFrom]
    rcases argmaxFrom_mem f as (if f best < f a then a else best) with h | h
    · split at h <;> simp_all
    · simp_all

theorem mem_finRange {K : Nat} (a : Fin K) : a ∈ List.finRange K :=
  List.mem_iff_getElem.mpr ⟨a.val, by simp, by simp⟩

/-- Argmax over all `K` arms (needs at least one arm). -/
def argmax {K : Nat} [NeZero K] (f : Arm K → Rat) : Arm K :=
  argmaxFrom f 0 (List.finRange K)

/-- **Spec of argmax**: the chosen arm scores at least as high as every arm. -/
theorem argmax_spec {K : Nat} [NeZero K] (f : Arm K → Rat) (a : Arm K) :
    f a ≤ f (argmax f) :=
  argmaxFrom_ge_mem f _ _ a (mem_finRange a)

end CB
