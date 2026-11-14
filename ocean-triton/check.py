"""Run the Triton kernels that tools/ocean-triton/ prints from Agda and compare them with the
exact values that agda/src/OceanTriton/Vectors.agda computes.

    python3 ocean-triton/check.py KERNELS.py VECTORS.json [--device cpu|cuda]

On cpu (the default) Triton runs in its interpreter (TRITON_INTERPRET=1), which executes the
same kernel source with NumPy in float32. Every output must be within ATOL + RTOL * |exact| of the
exact rational: the kernels compute in float32, so they round, and the tolerance is the budget
for that rounding, not a claim that Agda proves (AGENTS.md rule 7).
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
    ap.add_argument("kernels")
    ap.add_argument("vectors")
    ap.add_argument("--device", default="cpu", choices=["cpu", "cuda"])
    args = ap.parse_args()
    if args.device == "cpu":
        os.environ["TRITON_INTERPRET"] = "1"
    import torch  # after TRITON_INTERPRET, which Triton reads at import

    spec = importlib.util.spec_from_file_location("ocean_triton_kernels", args.kernels)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    with open(args.vectors, encoding="utf-8") as f:
        cases = json.load(f)

    if set(cases) != set(mod.KERNELS):
        print(f"ocean-triton: kernels {sorted(mod.KERNELS)} and cases {sorted(cases)} differ")
        return 1
    bad = 0
    for name, (fn, shape, arrays, scalars) in mod.KERNELS.items():
        case = cases[name]
        n = case["n"]
        ins = [torch.tensor([float(Fraction(v)) for v in case["arrays"][a]],
                            dtype=torch.float32, device=args.device) for a in arrays]
        scs = [float(Fraction(case["scalars"][s])) for s in scalars]
        exact = [Fraction(v) for v in case["expected"]]
        out = torch.zeros(len(exact), dtype=torch.float32, device=args.device)
        grid = (1,) if shape == "reduce" else (triton_cdiv(n, BLOCK),)
        loop = (case["iters"],) if shape == "loop" else ()
        fn[grid](*ins, *scs, out, n, *loop, BLOCK=BLOCK)
        got = out.cpu().tolist()
        worst = max(abs(g - float(e)) / (ATOL + RTOL * abs(float(e))) for g, e in zip(got, exact))
        ok = worst <= 1.0
        bad += not ok
        print(f"{'OK  ' if ok else 'FAIL'} {name:18} {shape:6} {len(exact):3} values, "
              f"worst error {worst:.3f} of the budget")
    print(f"ocean-triton: {len(mod.KERNELS) - bad}/{len(mod.KERNELS)} kernels agree with Agda "
          f"({args.device}{', interpreter' if args.device == 'cpu' else ''})")
    return 1 if bad else 0


def triton_cdiv(a: int, b: int) -> int:
    return (a + b - 1) // b


if __name__ == "__main__":
    sys.exit(main())
