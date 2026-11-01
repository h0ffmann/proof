import ContextualBandit.Argmax

/-!
# Decision rules

Each rule takes the model's per-arm estimates `est : Arm K → Estimate`
and returns a probability for every arm.

* `greedy`: argmax of the mean (pure exploitation).
* `ucb β`: argmax of `mean + β * width` (optimism in the face of uncertainty).
  With a Bayesian linear model this is LinUCB.
* `epsGreedy ε`: with probability `ε` pick uniformly, otherwise greedy.

Thompson sampling is also "argmax", but of a *sampled* mean. In this spec it is
`greedy` applied to estimates drawn from the posterior; the Haskell port shows
the sampling.
-/

namespace CB

/-- Point mass on one arm. -/
def point {K : Nat} (b : Arm K) : Decision K := fun a => if a = b then 1 else 0

/-- Uniform over all `K` arms. -/
def uniform (K : Nat) : Decision K := fun _ => invK K

/-- Mixture `w * d₁ + (1 - w) * d₂`. -/
def mix {K : Nat} (w : Rat) (d₁ d₂ : Decision K) : Decision K :=
  fun a => w * d₁ a + (1 - w) * d₂ a

/-- UCB score of an estimate. -/
def ucbScore (β : Rat) (e : Estimate) : Rat := e.mean + β * e.width

def greedyArm {K : Nat} [NeZero K] (est : Arm K → Estimate) : Arm K :=
  argmax (fun a => (est a).mean)

def ucbArm {K : Nat} [NeZero K] (β : Rat) (est : Arm K → Estimate) : Arm K :=
  argmax (fun a => ucbScore β (est a))

def greedy {K : Nat} [NeZero K] : DecisionRule K :=
  fun est => point (greedyArm est)

def ucb {K : Nat} [NeZero K] (β : Rat) : DecisionRule K :=
  fun est => point (ucbArm β est)

def epsGreedy {K : Nat} [NeZero K] (ε : Rat) : DecisionRule K :=
  fun est => mix ε (uniform K) (point (greedyArm est))

/-- Total probability mass of a decision. -/
def mass {K : Nat} (d : Decision K) : Rat := ((List.finRange K).map d).sum

/-- A decision is a valid probability distribution. -/
def Decision.Valid {K : Nat} (d : Decision K) : Prop :=
  (∀ a, 0 ≤ d a) ∧ mass d = 1

end CB
