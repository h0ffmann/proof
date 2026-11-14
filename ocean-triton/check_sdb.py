"""Run the W3SDB1 kernels that tools/ocean-triton/ prints from agda/src/OceanTriton/W3SDB1.agda
and compare them with the values of the same routine in Agda's Float (sdb_vectors.json).

    python3 ocean-triton/check_sdb.py SDB.py SDB_VECTORS.json [--device cpu|cuda]

Each case runs the kernel of its FDONLY on five spectral points. The kernel computes CBJ in
float64 and stores D and S in float32, so every value must be within ATOL + RTOL * |exact| of
the double the Agda computes, the float32 budget of check.py. Both sides use a host's exp and
sqrt, and tanh differs (Agda's is the host's, the kernel's is built from exp): the budget covers
that, and this is a check of the printed program, not of the functions.
"""

import argparse
import importlib.util
import json
import os
import sys
import warnings

RTOL = 1e-5
ATOL = 1e-6
BLOCK = 16


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("sdb")
    ap.add_argument("vectors")
    ap.add_argument("--device", default="cpu", choices=["cpu", "cuda"])
    args = ap.parse_args()
    if args.device == "cpu":
        os.environ["TRITON_INTERPRET"] = "1"
    import torch  # after TRITON_INTERPRET, which Triton reads at import

    # The branch not taken of a tl.where may divide by zero; nothing reads it.
    warnings.filterwarnings("ignore", category=RuntimeWarning)
    spec = importlib.util.spec_from_file_location("ocean_triton_sdb", args.sdb)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    with open(args.vectors, encoding="utf-8") as f:
        cases = json.load(f)
    dev, bad = args.device, 0
    for c in cases:
        A = torch.tensor([float(a) for a in c["A"]], dtype=torch.float32, device=dev)
        p = torch.tensor([float(x) for x in c["inputs"]], dtype=torch.float64, device=dev)
        n = A.numel()
        s = torch.zeros(n, dtype=torch.float32, device=dev)
        d = torch.zeros(n, dtype=torch.float32, device=dev)
        mod.KERNELS[c["fdonly"]][((n + BLOCK - 1) // BLOCK,)](A, p, s, d, n, BLOCK=BLOCK)
        exact = [float(c["D"])] * n + [float(x) for x in c["S"]]
        got = d.cpu().tolist() + s.cpu().tolist()
        worst = max(abs(g - e) / (ATOL + RTOL * abs(e)) for g, e in zip(got, exact))
        ok = worst <= 1.0
        bad += not ok
        print(f"{'OK  ' if ok else 'FAIL'} w3sdb1 {c['name']:28} worst {worst:.3f} of the budget")
    print(f"check_sdb: {len(cases) - bad}/{len(cases)} cases agree ({dev})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
