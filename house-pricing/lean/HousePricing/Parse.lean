import HousePricing.Tree

/-!
# Reading the exported model

The Rust trainer writes `model/*.txt`:

```
gbt <features> <trees> <base>
N <feature> <threshold> <left> <right>   or   L <value>     (pre-order, one tree per line)
```

Numbers are plain decimals (`-12.5`), read here as exact `Rat`. The parser is
only a loader: no theorem depends on it, since every theorem holds for every
`Ensemble`.
-/

namespace HP

/-- `"-12.05"` ↦ `-241/20`, exactly. -/
def parseDecimal (s : String) : Option Rat :=
  let (neg, body) := if s.startsWith "-" then (true, s.drop 1) else (false, s)
  match body.splitOn "." with
  | [i] => do
      let a ← i.toNat?
      pure (if neg then -(a : Rat) else a)
  | [i, f] => do
      let a ← (if i.isEmpty then some 0 else i.toNat?)
      let b ← (if f.isEmpty then some 0 else f.toNat?)
      let q := mkRat ((a * 10 ^ f.length + b : Nat) : Int) (10 ^ f.length)
      pure (if neg then -q else q)
  | _ => none

/-- One tree in pre-order. `fuel` bounds the recursion (the token count is enough). -/
def parseTree (n : Nat) : Nat → List String → Option (Tree n × List String)
  | 0, _ => none
  | _ + 1, "L" :: v :: rest => do
      pure (.leaf (← parseDecimal v), rest)
  | fuel + 1, "N" :: f :: t :: rest => do
      let k ← f.toNat?
      let fi ← if h : k < n then some (⟨k, h⟩ : Fin n) else none
      let th ← parseDecimal t
      let (l, rest) ← parseTree n fuel rest
      let (r, rest) ← parseTree n fuel rest
      pure (.node fi th l r, rest)
  | _, _ => none

def parseTrees (n : Nat) (fuel : Nat) : Nat → List String → Option (List (Tree n) × List String)
  | 0, rest => some ([], rest)
  | k + 1, toks => do
      let (t, rest) ← parseTree n fuel toks
      let (ts, rest) ← parseTrees n fuel k rest
      pure (t :: ts, rest)

def tokens (s : String) : List String :=
  (s.split fun c => c == ' ' || c == '\n' || c == '\r' || c == '\t').filter (· ≠ "")

def parseEnsemble (n : Nat) (s : String) : Option (Ensemble n) := do
  let toks := tokens s
  match toks with
  | "gbt" :: nf :: nt :: b :: rest =>
      if nf.toNat? ≠ some n then none else
      let k ← nt.toNat?
      let base ← parseDecimal b
      let (trees, rest) ← parseTrees n toks.length k rest
      if rest.isEmpty then some { base, trees } else none
  | _ => none

end HP
