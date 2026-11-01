# A formal circle {#sec:formal}

**[SKELETON: the proposition as a theorem. The Lean file is `cycle/lean/Cycle/Clock.lean`.]**

Model: a world has $n + 1$ moments. One tick moves moment $t$ to $(t + 1) \bmod (n + 1)$.
Lean proves four facts about this clock with no `sorry` and no Mathlib.

| Theorem | Statement |
|---|---|
| `tick_iterate` | after $k$ ticks, moment $t$ becomes $(t + k) \bmod (n + 1)$ |
| `eternal_return` | after $n + 1$ ticks, every moment is itself again |
| `history_periodic` | the moment at time $k + n + 1$ equals the moment at time $k$ |
| `returns_forever` | every moment returns after $m(n + 1)$ ticks, for every $m$ |

: The four theorems of `Cycle/Clock.lean`. {#tbl:clock}

To argue:

- [@Tbl:clock] makes the proposition exact, but the model assumes the circle. The proof shows
  that a circle returns. It does not show that time is a circle.
- The general result is stronger: any map on a finite set of states that is a bijection is
  periodic. **[TODO: prove it in Lean (pigeonhole on orbits), or say why it is left out.]**
- What a proof can carry into an essay, and what it cannot.
