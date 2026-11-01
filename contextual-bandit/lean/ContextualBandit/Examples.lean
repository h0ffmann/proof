import ContextualBandit.Theorems

/-!
# A concrete model you can `#eval`

`Tabular` keeps, for each (context, arm), a reward sum and a pull count.
* mean  = sum / count (0 if never pulled)
* width = 1 / (count + 1). This is a rational stand-in for `1/√n`, since core
  Lean has no square root on `Rat`. The Haskell port uses the real `1/√n`.
-/

namespace CB.Examples

open CB

inductive Ctx | morning | evening
  deriving DecidableEq, Repr

/-- Belief: a function from (context, arm) to (reward sum, count). -/
abbrev Tab (K : Nat) := Ctx → Arm K → Rat × Nat

def tabular (K : Nat) : RewardModel Ctx K (Tab K) where
  prior := fun _ _ => (0, 0)
  update := fun b o => fun c a =>
    if c = o.context ∧ a = o.arm then ((b c a).1 + o.reward, (b c a).2 + 1) else b c a
  estimate := fun b c a =>
    let (s, n) := b c a
    { mean := if n = 0 then 0 else s / n, width := 1 / ((n : Rat) + 1) }

/-- Three arms; in the morning arm 1 pays off, in the evening arm 2. -/
def history : List (Obs Ctx 3) :=
  [ ⟨.morning, 0, 0⟩, ⟨.morning, 1, 1⟩, ⟨.morning, 1, 1⟩, ⟨.morning, 2, 0⟩,
    ⟨.evening, 0, 0⟩, ⟨.evening, 1, 0⟩, ⟨.evening, 2, 1⟩ ]

def show3 (d : Decision 3) : List Rat := (List.finRange 3).map d

#eval show3 (policy (tabular 3) greedy history .morning)          -- [0, 1, 0]
#eval show3 (policy (tabular 3) greedy history .evening)          -- [0, 0, 1]
#eval show3 (policy (tabular 3) (epsGreedy (1/10)) history .morning)
-- [1/30, 14/15, 1/30]

/-- Every rule's output is a distribution here too: this is the general theorem, applied. -/
example : (policy (tabular 3) (epsGreedy (1/10)) history .morning).Valid :=
  epsGreedy_valid _ (by native_decide) (by native_decide) _

end CB.Examples
