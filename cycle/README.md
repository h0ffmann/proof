# cycle: eternal return

The proposition: *time is a flat circle*. Every moment returns, exactly and forever.

This folder holds the formal half of an essay. The essay itself is a Paper Fabric paper in
[`papers/cycle/`](../papers/cycle/metadata.md); build it with `just paper cycle`.

## Lean

`lean/` is the Lake package `Cycle` (core Lean only, same toolchain as the other packages).
`Cycle/Clock.lean` models time as a clock with `n + 1` moments and proves:

| Theorem | Statement |
|---|---|
| `tick_iterate` | after `k` ticks, moment `t` becomes `(t + k) mod (n + 1)` |
| `eternal_return` | after `n + 1` ticks, every moment is itself again |
| `history_periodic` | the history repeats with period `n + 1` |
| `returns_forever` | every moment returns after every multiple of `n + 1` ticks |

```bash
cd cycle/lean && lake build
```

## Next steps

- Recurrence for any bijection on a finite set of states (pigeonhole on orbits), in core Lean.
- Poincaré recurrence for measure-preserving maps (needs Mathlib).
