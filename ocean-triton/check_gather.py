"""Run the gather kernels and programs that tools/ocean-triton/ prints from
agda/src/OceanTriton/ (Gather, Shallow, Mesh, W3SBT1, W3SNL1) and compare them with the exact
values of agda/src/OceanTriton/GatherVectors.agda.

    python3 ocean-triton/check_gather.py GATHER.py GATHER_VECTORS.json [--device cpu|cuda]

A kernel case runs one kernel on its arrays. A program case runs its launches in the printed
order, `runs` times, each launch into a fresh buffer of its lane count, which is what
`OceanTriton.Gather.stepsG` means. Before a launch, every index read is checked to be inside the
buffer it reads, and every count of a `rep` (REP_BOUNDS) to be at most its R: the printed loop
means `repN` only there. Every value must be within ATOL + RTOL * |exact| of the exact rational,
the budget of check.py; it is a rounding budget, not a claim that Agda proves.
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


def budget(got: float, exact: Fraction) -> float:
    return abs(got - float(exact)) / (ATOL + RTOL * abs(float(exact)))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("gather")
    ap.add_argument("vectors")
    ap.add_argument("--device", default="cpu", choices=["cpu", "cuda"])
    args = ap.parse_args()
    if args.device == "cpu":
        os.environ["TRITON_INTERPRET"] = "1"
    import torch  # after TRITON_INTERPRET, which Triton reads at import

    spec = importlib.util.spec_from_file_location("ocean_triton_gather", args.gather)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    with open(args.vectors, encoding="utf-8") as f:
        cases = json.load(f)
    dev = args.device

    def f32(xs):
        return torch.tensor([float(Fraction(v)) for v in xs], dtype=torch.float32, device=dev)

    def i32(xs):
        return torch.tensor(xs, dtype=torch.int32, device=dev)

    def launch(name, arrays, idxs, scalars, n):
        fn, fused = mod.KERNELS[name]
        for k, r in mod.REP_BOUNDS.get(name, ()):
            top = int(idxs[k][:n].max()) if n else 0
            if top > r:
                raise ValueError(f"{name}: a count {top} is above R = {r}")
        out = torch.zeros(n, dtype=torch.float32, device=dev)
        grid = (1,) if fused else ((n + BLOCK - 1) // BLOCK,)
        fn[grid](*arrays, *idxs, *scalars, out, n, BLOCK=BLOCK)
        return out

    def compare(label, got, exact):
        worst = max((budget(g, e) for g, e in zip(got, exact)), default=0.0)
        ok = len(got) == len(exact) and worst <= 1.0
        print(f"{'OK  ' if ok else 'FAIL'} {label}: worst {worst:.3f} of the budget")
        return ok

    bad = 0
    used = {fn.fn.__name__ for *_, launches, _ in mod.PROGRAMS.values() for fn, *_ in launches}
    missing = set(mod.KERNELS) - set(cases["kernels"]) - used
    if missing or set(cases["programs"]) != set(mod.PROGRAMS) or not set(cases["kernels"]) <= set(mod.KERNELS):
        print(f"ocean-triton: kernels without a case {sorted(missing)}, or programs and cases differ")
        return 1

    for name, case in cases["kernels"].items():
        n = case["n"]
        got = launch(name, [f32(a) for a in case["arrays"]], [i32(j) for j in case["idxs"]],
                     [float(Fraction(s)) for s in case["scalars"]], n).cpu().tolist()
        bad += not compare(f"{name:12} {n} lanes", got, [Fraction(v) for v in case["expected"]])

    for name, (buffers, indices, params, sizes, launches, results) in mod.PROGRAMS.items():
        case = cases["programs"][name]
        bufs = {b: f32(case["buffers"].get(b, [0])) for b in buffers}
        ixs = {x: i32(case["indices"][x]) for x in indices}
        ps = {p: float(Fraction(case["params"][p])) for p in params}
        ls = {s: case["sizes"][s] for s in sizes}
        for _ in range(case["runs"]):
            for fn, fused, reads, xs, scs, lanes, writes in launches:
                n = ls[lanes]
                for x in xs:
                    if len(ixs[x]) < n:
                        raise ValueError(f"{name}: index array {x} is shorter than {n} lanes")
                bufs[writes] = launch(fn.fn.__name__, [bufs[b] for b in reads], [ixs[x] for x in xs],
                                      [ps[p] for p in scs], n)
        for b, s in results:
            got = bufs[b].cpu().tolist()
            bad += not compare(f"{name:12} {b} on {ls[s]} lanes, {case['runs']} runs of {len(launches)} launches",
                               got, [Fraction(v) for v in case["expected"][b]])

    total = len(cases["kernels"]) + sum(len(r[-1]) for r in mod.PROGRAMS.values())
    print(f"ocean-triton: {total - bad}/{total} gather results agree with Agda "
          f"({dev}{', interpreter' if dev == 'cpu' else ''})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
