"""Replay a capture of WAVEWATCH III's routines through the Triton kernels printed from Agda, and
compare them with the Fortran's own outputs (milestone M5 of ocean-triton/PLAN.md, the W mark).

    python3 ww3-replay/replay.py GATHER.py CAPTURE.txt [--sdb SDB.py] [--bits] [--device cpu|cuda]

CAPTURE.txt is what ww3-replay/ww3_capture.F90 writes: the inputs of W3SNL1, W3SBT1 and W3SDB1
at one sea point of a WW3 run, INSNL1's tables, and the three routines' S and D as WW3 computed
them, every REAL with nine significant digits (it reads back to the same float32).

The Agda programs index the extended arrays of W3SNL1 from 0 (W3SNL1.agda, "Positions"): a
position p is ISP + NTH - 1, and a table holds positions. This script turns WW3's tables into
that form and nothing else; the kernels, their launch order and their buffers are the printed
PROGRAMS and KERNELS of GATHER.py, and W3SDB1's kernel of SDB.py.

The budget, written down before the first run: a value agrees when
|triton - ww3| <= ATOL * max|ww3| + RTOL * |ww3|, with ATOL = 1e-6 and RTOL = 1e-5, the
float32 budget of ocean-triton/check.py with its absolute part scaled to the routine's output.
Each line also reports how many values are bit for bit the Fortran's; with --bits, an output
passes only when all of them are.
"""

import argparse
import importlib.util
import os
import sys

RTOL = 1e-5
ATOL = 1e-6
BLOCK = 16


def read_capture(path):
    with open(path, encoding="utf-8") as f:
        lines = [ln.strip() for ln in f if ln.strip()]
    dims = [int(x) for x in lines[0].split()[1:]]
    out, i = {}, 1
    while i < len(lines):
        name, n = lines[i].split()
        n = int(n)
        vals = lines[i + 1:i + 1 + n]
        out[name] = [int(v) for v in vals] if name in ("ip", "ic") else [float(v) for v in vals]
        i += 1 + n
    keys = ("nth", "nk", "nspec", "nfr", "nfrhgh", "nfrchg", "nspecx", "nspecy", "isea")
    return dict(zip(keys, dims)), out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("gather")
    ap.add_argument("capture")
    ap.add_argument("--sdb", default="ocean-triton/sdb.py", help="the printed W3SDB1 module")
    ap.add_argument("--bits", action="store_true")
    ap.add_argument("--device", default="cpu", choices=["cpu", "cuda"])
    args = ap.parse_args()
    if args.device == "cpu":
        os.environ["TRITON_INTERPRET"] = "1"
    import torch  # after TRITON_INTERPRET, which Triton reads at import

    spec = importlib.util.spec_from_file_location("ocean_triton_gather", args.gather)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    d, c = read_capture(args.capture)
    dev = args.device
    nth, nk, nspec, nfr = d["nth"], d["nk"], d["nspec"], d["nfr"]
    nue, nsa = nth + d["nspecy"], nth + d["nspecx"]
    depth, _emean, _fmean, _wnmean, tpiinv, fachfe, cons, dal1, dal2, dal3, sbtc1 = c["scalars"]

    def f32(xs):
        return torch.tensor(xs, dtype=torch.float32, device=dev)

    def i32(xs):
        return torch.tensor(xs, dtype=torch.int32, device=dev)

    def launch(name, arrays, idxs, scalars, n):
        fn, fused = mod.KERNELS[name]
        for k, r in mod.REP_BOUNDS.get(name, ()):
            top = int(idxs[k][:n].max())
            if top > r:
                raise ValueError(f"{name}: a count {top} is above R = {r}; print the kernel with a larger R")
        out = torch.zeros(n, dtype=torch.float32, device=dev)
        grid = (1,) if fused else ((n + BLOCK - 1) // BLOCK,)
        fn[grid](*arrays, *idxs, *scalars, out, n, BLOCK=BLOCK)
        return out

    def compare(label, got, ref):
        got = [float(g) for g in got]
        top = max(abs(r) for r in ref) or 1.0
        worst = max(abs(g - r) / (ATOL * top + RTOL * abs(r)) for g, r in zip(got, ref))
        same = sum(1 for g, r in zip(got, ref) if torch.tensor(g, dtype=torch.float32).item()
                   == torch.tensor(r, dtype=torch.float32).item())
        ok = len(got) == len(ref) and worst <= 1.0 and (same == len(ref) or not args.bits)
        print(f"{'OK  ' if ok else 'FAIL'} {label:30} {len(ref):5} values, worst {worst:.3f} of the budget, "
              f"{same} bit for bit")
        return ok

    # W3SNL1: the program w3snl1, its buffers and tables in the positions of W3SNL1.agda.
    def row(p):
        return max(p - nth, 0) // nth

    def col(p):
        return max(p - nth, 0) % nth

    msk = [0.0 if p < nth else 1.0 for p in range(nue)]
    src = [col(p) + min(row(p), nfr - 1) * nth for p in range(nue)]
    kof = [min(row(p), nfr - 1) for p in range(nue)]
    cnt = [max(row(p) - (nfr - 1), 0) for p in range(nue)]
    af11 = [0.0] * nth + c["af11"]
    nx = d["nspecx"]
    ip = [[0] * nth + [v + nth - 1 for v in c["ip"][t * nx:(t + 1) * nx]] for t in range(16)]
    ic = [[v + nth - 1 for v in c["ic"][t * nspec:(t + 1) * nspec]] for t in range(16)]
    ipn = ["ip11", "ip12", "ip13", "ip14", "im11", "im12", "im13", "im14",
           "ip21", "ip22", "ip23", "ip24", "im21", "im22", "im23", "im24"]
    icn = ["ic11", "ic12", "ic21", "ic22", "ic31", "ic32", "ic41", "ic42",
           "ic51", "ic52", "ic61", "ic62", "ic71", "ic72", "ic81", "ic82"]
    if any(min(t) < 0 or max(t) >= nue for t in ip) or any(min(t) < 0 or max(t) >= nsa for t in ic):
        raise ValueError("a table of INSNL1 points outside the extended arrays")

    buffers, indices, params, sizes, launches, results = mod.PROGRAMS["w3snl1"]
    bufs = {"A": f32(c["A"]), "sig": f32(c["sig"][:nfr]), "cg": f32(c["cg"][:nfr]),
            "msk": f32(msk), "af11": f32(af11)}
    ixs = {"src": i32(src), "kof": i32(kof), "cnt": i32(cnt),
           "kofS": i32([q // nth for q in range(nspec)]), "self": i32([q + nth for q in range(nspec)])}
    ixs.update({n: i32(t) for n, t in zip(ipn, ip)})
    ixs.update({n: i32(t) for n, t in zip(icn, ic)})
    ps = {"tpiinv": tpiinv, "fachfe": fachfe, "cons": cons, "dal1": dal1, "dal2": dal2, "dal3": dal3}
    ps.update({f"awg{k + 1}": v for k, v in enumerate(c["awg"])})
    ps.update({f"swg{k + 1}": v for k, v in enumerate(c["swg"])})
    ls = {"nue": nue, "nsa": nsa, "nspec": nspec}
    for fn, _fused, reads, xs, scs, lanes, writes in launches:
        bufs[writes] = launch(fn.fn.__name__, [bufs[b] for b in reads], [ixs[x] for x in xs],
                              [ps[p] for p in scs], ls[lanes])
    bad = 0
    bad += not compare("W3SNL1 S (11 launches)", bufs["S"].cpu().tolist(), c["SNL"])
    bad += not compare("W3SNL1 D (11 launches)", bufs["D"].cpu().tolist(), c["DNL"])

    # W3SBT1: the kernels w3sbt1_d and w3sbt1_s, with MAPWN(IS) the bin of IS.
    arrays = [f32(c["A"]), f32(c["wn"]), f32(c["cg"]), f32(c["sig"][:nk])]
    mapwn = [i32([q // nth for q in range(nspec)])]
    bad += not compare("W3SBT1 S", launch("w3sbt1_s", arrays, mapwn, [sbtc1, depth], nspec).cpu().tolist(), c["SBT"])
    bad += not compare("W3SBT1 D", launch("w3sbt1_d", arrays, mapwn, [sbtc1, depth], nspec).cpu().tolist(), c["DBT"])

    # W3SDB1: the kernel of its FDONLY, CBJ in float64 from the REAL inputs widened (DBLE).
    import warnings
    warnings.filterwarnings("ignore", category=RuntimeWarning)  # the branch not taken of a tl.where
    sdbc1, sdbc2, fdonly = c["sdbconst"]
    if sum(c["A"]) < 1e-15:
        raise ValueError("SUM(A) is below THR: W3SDB1 returns early (w3sdb1md.F90:198), which the kernel is not")
    sdb = importlib.util.spec_from_file_location("ocean_triton_sdb", args.sdb)
    smod = importlib.util.module_from_spec(sdb)
    sdb.loader.exec_module(smod)
    p = torch.tensor([_emean, _fmean, _wnmean, depth, sdbc1, sdbc2], dtype=torch.float64, device=dev)
    s_out = torch.zeros(nspec, dtype=torch.float32, device=dev)
    d_out = torch.zeros(nspec, dtype=torch.float32, device=dev)
    smod.KERNELS[fdonly == 1.0][((nspec + BLOCK - 1) // BLOCK,)](f32(c["A"]), p, s_out, d_out, nspec, BLOCK=BLOCK)
    bad += not compare("W3SDB1 S", s_out.cpu().tolist(), c["SDB"])
    bad += not compare("W3SDB1 D", d_out.cpu().tolist(), c["DDB"])

    print(f"ww3-replay: {6 - bad}/6 outputs of WW3 agree with the printed kernels "
          f"(sea point {d['isea']}, depth {depth} m, {dev}{', interpreter' if dev == 'cpu' else ''})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
