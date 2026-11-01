/-!
# Regression trees and their sum

A tree compares one feature with a threshold at each node and returns a
constant at a leaf. A gradient-boosted model is a base value plus a list of
trees. Everything is `Rat`, so evaluation is exact.
-/

namespace HP

inductive Tree (n : Nat) where
  | leaf (v : Rat)
  /-- go `l` when `x f ≤ t`, else `r` (the same rule as the Rust trainer) -/
  | node (f : Fin n) (t : Rat) (l r : Tree n)
  deriving Repr, Inhabited

namespace Tree

variable {n : Nat}

def eval : Tree n → (Fin n → Rat) → Rat
  | leaf v, _ => v
  | node f t l r, x => if x f ≤ t then l.eval x else r.eval x

def rmin (a b : Rat) : Rat := if a ≤ b then a else b
def rmax (a b : Rat) : Rat := if a ≤ b then b else a

/-- The smallest leaf. -/
def lo : Tree n → Rat
  | leaf v => v
  | node _ _ l r => rmin l.lo r.lo

/-- The largest leaf. -/
def hi : Tree n → Rat
  | leaf v => v
  | node _ _ l r => rmax l.hi r.hi

/-- A checkable certificate of monotonicity in feature `j`: at every split on
`j`, each leaf on the left is at most each leaf on the right. -/
def monoIn (j : Fin n) : Tree n → Bool
  | leaf _ => true
  | node f _ l r => l.monoIn j && r.monoIn j && (f != j || decide (l.hi ≤ r.lo))

def leaves : Tree n → Nat
  | leaf _ => 1
  | node _ _ l r => l.leaves + r.leaves

end Tree

structure Ensemble (n : Nat) where
  base : Rat
  trees : List (Tree n)
  deriving Repr, Inhabited

namespace Ensemble

variable {n : Nat}

def predict (m : Ensemble n) (x : Fin n → Rat) : Rat :=
  m.base + (m.trees.map (·.eval x)).sum

/-- Lower bound of every prediction: base plus the smallest leaf of each tree. -/
def lo (m : Ensemble n) : Rat := m.base + (m.trees.map Tree.lo).sum

/-- Upper bound of every prediction. -/
def hi (m : Ensemble n) : Rat := m.base + (m.trees.map Tree.hi).sum

def monoIn (m : Ensemble n) (j : Fin n) : Bool := m.trees.all (·.monoIn j)

def leaves (m : Ensemble n) : Nat := (m.trees.map Tree.leaves).sum

end Ensemble

end HP
