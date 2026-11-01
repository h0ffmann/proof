/-!
# Time as a flat circle

The proposition of the essay `papers/cycle/`, stated in its smallest exact form.

A world has `n + 1` moments. Time moves by one tick, and the tick after the last moment is
the first moment again. Under that model:

* `tick_iterate`: after `k` ticks you are at `(t + k) mod (n + 1)`.
* `eternal_return`: after `n + 1` ticks every moment is itself again.
* `history_periodic`: the whole history repeats with period `n + 1`.
* `returns_forever`: every moment comes back after every multiple of `n + 1` ticks.

Core Lean only. The general Poincaré recurrence theorem (any measure-preserving map on a finite
measure space) needs Mathlib and is a next step.
-/

namespace Cycle

/-- One moment on a circle of `n + 1` moments. -/
abbrev Moment (n : Nat) := Fin (n + 1)

/-- One tick of the clock: the moment after `t`, wrapping from the last moment to the first. -/
def tick (n : Nat) (t : Moment n) : Moment n :=
  ⟨(t.val + 1) % (n + 1), Nat.mod_lt _ (Nat.succ_pos n)⟩

/-- `run n k t` applies `tick` `k` times, starting at `t`. -/
def run (n : Nat) : Nat → Moment n → Moment n
  | 0, t => t
  | k + 1, t => run n k (tick n t)

/-- The moment `k` ticks after `t0`. -/
def history (n : Nat) (t0 : Moment n) (k : Nat) : Moment n :=
  run n k t0

/-- Closed form: `k` ticks after `t` is `(t + k) mod (n + 1)`. -/
theorem tick_iterate (n : Nat) (t : Moment n) (k : Nat) :
    (run n k t).val = (t.val + k) % (n + 1) := by
  induction k generalizing t with
  | zero => simp [run, Nat.mod_eq_of_lt t.isLt]
  | succ k ih =>
    rw [run, ih]
    simp only [tick]
    rw [Nat.mod_add_mod, Nat.add_assoc, Nat.add_comm 1 k]

/-- Eternal return: after `n + 1` ticks every moment is itself again. -/
theorem eternal_return (n : Nat) (t : Moment n) :
    run n (n + 1) t = t := by
  apply Fin.ext
  rw [tick_iterate, Nat.add_mod_right, Nat.mod_eq_of_lt t.isLt]

/-- The whole history repeats: the moment at time `k + (n + 1)` is the moment at time `k`. -/
theorem history_periodic (n : Nat) (t0 : Moment n) (k : Nat) :
    history n t0 (k + (n + 1)) = history n t0 k := by
  apply Fin.ext
  simp only [history]
  rw [tick_iterate, tick_iterate, ← Nat.add_assoc, Nat.add_mod_right]

/-- Every moment comes back after every multiple of `n + 1` ticks, so it comes back forever. -/
theorem returns_forever (n : Nat) (t : Moment n) (m : Nat) :
    run n (m * (n + 1)) t = t := by
  apply Fin.ext
  rw [tick_iterate, Nat.add_mul_mod_self_right, Nat.mod_eq_of_lt t.isLt]

end Cycle
