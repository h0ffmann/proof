/-!
# Contextual bandit interface

The design splits a contextual bandit into two layers:

* a **reward model** (the probabilistic part): a belief state `B` that is updated
  with observations `(context, arm, reward)` and that can summarise, for every
  context and arm, a predicted mean reward and an uncertainty width;
* a **decision rule** (the bandit part): a function that only looks at the
  model's summary of the current context and returns a distribution over arms.

The decision rules here never see the raw history. They see it only through the
model. That boundary is what lets you swap in another model (Beta-Bernoulli,
Bayesian linear regression, a neural net with calibrated uncertainty, ...)
without touching the decision layer, and vice versa.

Everything is over `Rat` so the spec is exact and executable (`#eval`).
It uses only Lean core, with no Mathlib.
-/

namespace CB

/-- Arms are `Fin K`: exactly `K` of them. -/
abbrev Arm (K : Nat) := Fin K

/-- One round of interaction. -/
structure Obs (C : Type) (K : Nat) where
  context : C
  arm     : Arm K
  reward  : Rat

/-- What a model reports about one (context, arm) pair. -/
structure Estimate where
  /-- Predicted (posterior / predictive) mean reward. -/
  mean  : Rat
  /-- Uncertainty: a standard deviation or confidence radius. Must be `≥ 0`. -/
  width : Rat

/-- A probabilistic reward model with belief state `B`. -/
structure RewardModel (C : Type) (K : Nat) (B : Type) where
  prior    : B
  update   : B → Obs C K → B
  estimate : B → C → Arm K → Estimate

/-- A randomised decision: a probability for every arm. -/
abbrev Decision (K : Nat) := Arm K → Rat

/-- A decision rule maps the model's per-arm estimates to a distribution over arms.
It is deliberately *not* given the context or the history directly. -/
abbrev DecisionRule (K : Nat) := (Arm K → Estimate) → Decision K

/-- The belief after replaying a history (oldest first). -/
def RewardModel.posterior {C B : Type} {K : Nat} (m : RewardModel C K B)
    (h : List (Obs C K)) : B :=
  h.foldl m.update m.prior

/-- A bandit agent = model + decision rule. Its policy is
`history → context → distribution over arms`. -/
def policy {C B : Type} {K : Nat} (m : RewardModel C K B) (rule : DecisionRule K)
    (h : List (Obs C K)) (c : C) : Decision K :=
  rule (m.estimate (m.posterior h) c)

/-- The uniform-over-arms helper `1/K` (as `0` when `K = 0`). -/
def invK (K : Nat) : Rat := (K : Rat)⁻¹

end CB
