"""Run the lane programs that tools/ocean-triton/ prints from agda/src/OceanTriton/ (Lanes,
EmitLanes, W3SDS4) and compare them with the values of the same routines in Agda's Float
(lanes_vectors.json).

    python3 ocean-triton/check_lanes.py LANES.py LANES_VECTORS.json [--device cpu|cuda]

A case gives a program's input arrays and parameters. Every other float array starts at zero.
The launches run in the printed order, each into a fresh buffer of its lane count, which is
what `OceanTriton.Lanes.runL` means. The kernels compute in float32 and the exact values are
the routine in double, so a value agrees when |got - exact| <= ATOL * max|exact| + RTOL * |exact|,
with ATOL = 1e-6 and RTOL = 1e-5: the float32 budget of check.py, its absolute part scaled to
the result (dissipation rates are small numbers). The functions differ too (tanh and pow are
built from exp and log in the kernel, and `vpow` is libmvec's powf, ocean-triton/libmvec.py);
the budget covers that on these inputs, and this is a check of the printed programs, not of the
functions. `libmvec.py --self-test` checks vpow against the library.
"""

import argparse
import importlib.util
import json
import os
import sys
import warnings

RTOL = 1e-5
ATOL = 1e-6
BLOCK = 1024


_MV = {}


def run(mod, prog, farrs, iarrs, fps, ips, torch, dev):
    """The launches of PROGRAMS_L[prog] on these inputs; returns every float buffer."""
    if dev not in _MV:  # libmvec's tables and this CPU's rcpps, for `vpow` (libmvec.py)
        import libmvec
        _MV[dev] = torch.tensor(libmvec.tables(), dtype=torch.float64, device=dev)
    fnames, inames, fpn, ipn, launches, _results = mod.PROGRAMS_L[prog]
    bufs = {f: torch.tensor([float(v) for v in farrs[f]], dtype=torch.float32, device=dev)
            if f in farrs else torch.zeros(1, dtype=torch.float32, device=dev) for f in fnames}
    ibufs = [torch.tensor(iarrs[n], dtype=torch.int32, device=dev) for n in inames]
    fvals = [float(fps[n]) for n in fpn]
    ivals = [int(ips[n]) for n in ipn]
    for fn, lanes, out in launches:
        n = int(ips[lanes])
        res = torch.zeros(n, dtype=torch.float32, device=dev)
        fn[((n + BLOCK - 1) // BLOCK,)](*[bufs[f] for f in fnames], *ibufs, *fvals, *ivals, _MV[dev], res, n, BLOCK=BLOCK)
        bufs[out] = res
    return bufs


def compare(label, got, ref, bits=False):
    import torch
    top = max(abs(r) for r in ref) or 1.0
    worst = max(abs(g - r) / (ATOL * top + RTOL * abs(r)) for g, r in zip(got, ref))
    same = sum(1 for g, r in zip(got, ref) if torch.tensor(g, dtype=torch.float32).item()
               == torch.tensor(r, dtype=torch.float32).item())
    ok = len(got) == len(ref) and worst <= 1.0 and (same == len(ref) or not bits)
    print(f"{'OK  ' if ok else 'FAIL'} {label:34} {len(ref):5} values, worst {worst:.3f} of the budget, "
          f"{same} bit for bit")
    return ok


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("lanes")
    ap.add_argument("vectors")
    ap.add_argument("--device", default="cpu", choices=["cpu", "cuda"])
    args = ap.parse_args()
    if args.device == "cpu":
        os.environ["TRITON_INTERPRET"] = "1"
    import torch  # after TRITON_INTERPRET, which Triton reads at import

    # The branch not taken of a tl.where may divide by zero or take a log of 0; nothing reads it.
    warnings.filterwarnings("ignore", category=RuntimeWarning)
    spec = importlib.util.spec_from_file_location("ocean_triton_lanes", args.lanes)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    with open(args.vectors, encoding="utf-8") as f:
        progs = json.load(f)
    if set(progs) != set(mod.PROGRAMS_L):
        print(f"check_lanes: programs {sorted(mod.PROGRAMS_L)} and cases {sorted(progs)} differ")
        return 1
    bad = total = 0
    for prog, cases in progs.items():
        results = mod.PROGRAMS_L[prog][5]
        for c in cases:
            bufs = run(mod, prog, c["farrays"], c["iarrays"], c["fparams"], c["iparams"], torch, args.device)
            for b, size in results:
                n = int(c["iparams"][size])
                total += 1
                bad += not compare(f"{prog} {c['name']} {b}", bufs[b].cpu().tolist()[:n],
                                   [float(v) for v in c["expected"][b]])
    print(f"check_lanes: {total - bad}/{total} results agree ({args.device})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
