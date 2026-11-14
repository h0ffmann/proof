"""Run the launch programs that tools/ocean-triton/ prints from agda/src/OceanTriton/Space.agda
and compare their result with the exact values of agda/src/OceanTriton/GridVectors.agda.

    python3 ocean-triton/check_grid.py GRID.py GRID_VECTORS.json [--device cpu|cuda]

Each program runs its launches in the printed order, `runs` times, each launch into a fresh
buffer, which is what `OceanTriton.Grid.steps` means. Every cell of the result must be within
ATOL + RTOL * |exact| of the exact rational, the budget of check.py, and so must the total of the
field. The tolerance is a rounding budget, not a claim that Agda proves (AGENTS.md rule 7).
"""

import argparse
import importlib.util
import json
import os
import sys
from fractions import Fraction

RTOL = 1e-5
ATOL = 1e-6
BLOCK = 16


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("grid")
    ap.add_argument("vectors")
    ap.add_argument("--device", default="cpu", choices=["cpu", "cuda"])
    args = ap.parse_args()
    if args.device == "cpu":
        os.environ["TRITON_INTERPRET"] = "1"
    import torch  # after TRITON_INTERPRET, which Triton reads at import

    spec = importlib.util.spec_from_file_location("ocean_triton_grid", args.grid)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    with open(args.vectors, encoding="utf-8") as f:
        cases = json.load(f)

    if set(cases) != set(mod.PROGRAMS):
        print(f"ocean-triton: programs {sorted(mod.PROGRAMS)} and cases {sorted(cases)} differ")
        return 1

    def budget(got: float, exact: Fraction) -> float:
        return abs(got - float(exact)) / (ATOL + RTOL * abs(float(exact)))

    bad = 0
    for name, (buffers, params, launches, result) in mod.PROGRAMS.items():
        case = cases[name]
        nx, ny, runs = case["nx"], case["ny"], case["runs"]
        bufs = {b: torch.tensor([float(Fraction(v)) for v in case["buffers"][b]],
                                dtype=torch.float32, device=args.device) for b in buffers}
        ps = {p: float(Fraction(case["params"][p])) for p in params}
        grid = ((nx * ny + BLOCK - 1) // BLOCK,)
        for _ in range(runs):
            for fn, reads, scalars, writes in launches:
                out = torch.zeros(nx * ny, dtype=torch.float32, device=args.device)
                fn[grid](*(bufs[b] for b in reads), *(ps[p] for p in scalars), out, nx, ny, BLOCK=BLOCK)
                bufs[writes] = out
        got = bufs[result].cpu().tolist()
        exact = [Fraction(v) for v in case["expected"]]
        worst = max(budget(g, e) for g, e in zip(got, exact))
        total = budget(sum(got), sum(exact))
        ok = worst <= 1.0 and total <= 1.0
        bad += not ok
        print(f"{'OK  ' if ok else 'FAIL'} {name:8} {nx} x {ny}, {runs} runs of {len(launches)} launches: "
              f"worst cell {worst:.3f}, total {total:.3f} of the budget")
    print(f"ocean-triton: {len(mod.PROGRAMS) - bad}/{len(mod.PROGRAMS)} programs agree with Agda "
          f"({args.device}{', interpreter' if args.device == 'cpu' else ''})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
