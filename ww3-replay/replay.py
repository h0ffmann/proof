"""Replay a capture of WAVEWATCH III's routines through the Triton kernels printed from Agda, and
compare them with the Fortran's own outputs (milestone M5 of ocean-triton/PLAN.md, the W mark).

    python3 ww3-replay/replay.py GATHER.py CAPTURE.txt [--sdb SDB.py] [--lanes LANES.py] [--bits]
                                 [--only R1,R2,...] [--srce] [--device cpu|cuda]

CAPTURE.txt is what ww3-replay/ww3_capture.F90 writes at one sea point of a WW3 run: the inputs
and outputs of W3SNL1, W3SBT1, W3SDB1, W3SDS4, W3SIN4, W3SPR4, W3SLN1 and WAVNU1, the tables of
INSNL1, INSIN4 and DISTAB, and a whole W3SRCE call, every REAL with nine significant digits (it
reads back to the same float32).

The Agda programs index the extended arrays of W3SNL1 from 0 (W3SNL1.agda, "Positions"): a
position p is ISP + NTH - 1, and a table holds positions. This script turns WW3's tables into
that form and nothing else; the kernels, their launch order and their buffers are the printed
PROGRAMS and KERNELS of GATHER.py, W3SDB1's kernel of SDB.py and the lane programs of LANES.py.
W3SRCE's loop is run by ww3-replay/srce.py on the same kernels (--srce, or --only W3SRCE).

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

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ocean-triton"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

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
        out[name] = [int(v) for v in vals] if name in ("ip", "ic", "sds4int", "SATI", "spr4int", "dispint", "insin4int") else [float(v) for v in vals]
        i += 1 + n
    keys = ("nth", "nk", "nspec", "nfr", "nfrhgh", "nfrchg", "nspecx", "nspecy", "isea")
    return dict(zip(keys, dims)), out


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("gather")
    ap.add_argument("capture")
    ap.add_argument("--sdb", default="ocean-triton/sdb.py", help="the printed W3SDB1 module")
    ap.add_argument("--lanes", default="ocean-triton/lanes.py", help="the printed lane programs (W3SDS4)")
    ap.add_argument("--bits", action="store_true")
    ap.add_argument("--srce", action="store_true", help="also replay a whole W3SRCE call (ww3-replay/srce.py)")
    ap.add_argument("--tables", action="store_true", help="also replay INSIN4's tables TAUT, TAUHFT and "
                    "TAUHFT2, which depend on the grid only")
    ap.add_argument("--plane", type=int, default=1, help="the plane I of TAUHFT2 to replay (default 1)")
    ap.add_argument("--only", default="", help="a comma-separated list of the routines to replay, "
                    "W3SNL1,W3SBT1,W3SDB1,W3SDS4,W3SIN4,W3SPR4,W3SLN1,WAVNU1,TABU_STRESS,TABU_TAUHF,TABU_TAUHF2,"
                    "INSIN4,W3SRCE (default: all but the tables and W3SRCE)")
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
        print(f"{'OK  ' if ok else 'FAIL'} {label:34} {len(ref):5} values, worst {worst:.3f} of the budget, "
              f"{same} bit for bit", flush=True)
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
    snl_ixs = {"src": i32(src), "kof": i32(kof), "cnt": i32(cnt),
               "kofS": i32([q // nth for q in range(nspec)]), "self": i32([q + nth for q in range(nspec)])}
    snl_ixs.update({n: i32(t) for n, t in zip(ipn, ip)})
    snl_ixs.update({n: i32(t) for n, t in zip(icn, ic)})

    def snl1(a, cns):
        _b, _i, _p, _s, launches, _r = mod.PROGRAMS["w3snl1"]
        bufs = {"A": f32(a), "sig": f32(c["sig"][:nfr]), "cg": f32(c["cg"][:nfr]), "msk": f32(msk), "af11": f32(af11)}
        ps = {"tpiinv": tpiinv, "fachfe": fachfe, "cons": cns, "dal1": dal1, "dal2": dal2, "dal3": dal3}
        ps.update({f"awg{k + 1}": v for k, v in enumerate(c["awg"])})
        ps.update({f"swg{k + 1}": v for k, v in enumerate(c["swg"])})
        ls = {"nue": nue, "nsa": nsa, "nspec": nspec}
        for fn, _fused, reads, xs, scs, lanes, writes in launches:
            bufs[writes] = launch(fn.fn.__name__, [bufs[b] for b in reads], [snl_ixs[x] for x in xs],
                                  [ps[p] for p in scs], ls[lanes])
        return bufs["S"].cpu().tolist(), bufs["D"].cpu().tolist()

    # W3SBT1: the kernels w3sbt1_d and w3sbt1_s, with MAPWN(IS) the bin of IS.
    mapwn = [i32([q // nth for q in range(nspec)])]

    def sbt1(a):
        arrays = [f32(a), f32(c["wn"]), f32(c["cg"]), f32(c["sig"][:nk])]
        return (launch("w3sbt1_s", arrays, mapwn, [sbtc1, depth], nspec).cpu().tolist(),
                launch("w3sbt1_d", arrays, mapwn, [sbtc1, depth], nspec).cpu().tolist())

    # W3SDB1: the kernel of its FDONLY, CBJ in float64 from the REAL inputs widened (DBLE).
    import warnings
    warnings.filterwarnings("ignore", category=RuntimeWarning)  # the branch not taken of a tl.where
    sdbc1, sdbc2, fdonly = c["sdbconst"]
    smod = load(args.sdb, "ocean_triton_sdb")

    def sdb1(a, em, fm, wm):
        if sum(a) < 1e-15:
            raise ValueError("SUM(A) is below THR: W3SDB1 returns early (w3sdb1md.F90:198), which the kernel is not")
        p = torch.tensor([em, fm, wm, depth, sdbc1, sdbc2], dtype=torch.float64, device=dev)
        s_out = torch.zeros(nspec, dtype=torch.float32, device=dev)
        d_out = torch.zeros(nspec, dtype=torch.float32, device=dev)
        smod.KERNELS[fdonly == 1.0][((nspec + BLOCK - 1) // BLOCK,)](f32(a), p, s_out, d_out, nspec, BLOCK=BLOCK)
        return s_out.cpu().tolist(), d_out.cpu().tolist()

    # The lane programs of LANES.py (W3SDS4, W3SIN4, W3SPR4, W3SLN1, W3SRCE's, WAVNU1).
    import check_lanes  # ocean-triton/check_lanes.py: the launches of a lane program, in order
    lmod = load(args.lanes, "ocean_triton_lanes")

    def lanes(prog, farrs, iarrs, fp, ip, outs):
        bufs = check_lanes.run(lmod, prog, farrs, iarrs, fp, ip, torch, dev)
        return [bufs[b].cpu().tolist() for b in outs]

    # W3SDS4, in the configuration it covers (W3SDS4.agda).
    ssdsc1, ssdsdth, brfdf, c8, c11, iso = c["sds4case"]
    if not (ssdsc1 == 1 and ssdsdth < 180 and brfdf == 0 and c8 == 0 and c11 == 0):
        raise ValueError(f"W3SDS4 is in a configuration the program does not cover: {c['sds4case']}")
    nsat, ik1, dik = c["sds4int"]
    sds4_fp = dict(zip(("dth", "ssdsbr", "ssdsc2", "ssdsc3", "ssdsc5", "ssdsc6", "ssdsc21", "ssdsp", "ssdsbm0",
                        "ssdsbm1", "ssdsbm2", "ssdsbm3", "ssdsbm4", "ustar", "usdir", "dair", "grav", "dwat",
                        "twopi2"), c["sds4const"]))
    sds4_fp["depth"] = depth
    sds4_ip = {"nth": nth, "nk": nk, "nspec": nspec, "nsat": nsat, "ik1": ik1 - 1, "dikcumul": dik,
               "iso1": 1 if iso == 1 else 0}

    def sds4(a, ust, usd):
        farrs = {"A": a, "K": c["wn"], "CG": c["cg"], "SIG": c["sig"][:nk], "ECOS": c["ECOS"],
                 "ESIN": c["ESIN"], "SATW": c["SATW"], "CUMULW": c["CUMULW"]}
        fp = dict(sds4_fp, ustar=ust, usdir=usd)
        s, dd = lanes("w3sds4", farrs, {"SATI": [v - 1 for v in c["SATI"]]}, fp, sds4_ip, ("S", "D"))
        return s[:nspec], dd[:nspec]

    # W3SIN4, every branch of it without STAB3 (W3SIN4.agda).
    iustar, ialpha, ilevtail, sizefw = (int(v) for v in c["sin4int"])
    sin4_fp = dict(zip(("u", "ustar", "usdir", "z0", "drat", "dth", "bbeta", "zzalp", "zz0rat", "shelt", "sw1",
                        "sw2", "sw3", "sw4", "sw5", "sw6", "sw7", "sinthp", "aalpha", "delust", "delalp", "deltail",
                        "delab", "abmin", "grav", "nuair", "kappa", "tpi"), c["sin4const"]))
    sin4_ip = {"nth": nth, "nk": nk, "nspec": nspec, "nk1": nk + 1, "n4": 4, "n6": 6, "iustar": iustar,
               "ialpha": ialpha, "ilevtail": ilevtail, "sizefw": sizefw}
    k2 = [c["wn"][q // nth] for q in range(nspec)]

    def sin4(a, **fp):
        farrs = {"A": a, "CG": c["cg"], "K": k2, "SIG": c["sig"][:nk], "SIG2": c["SIG2"], "DDEN": c["DDEN"],
                 "DDEN2": c["DDEN2"], "ECOS": c["ECOS2"], "ESIN": c["ESIN2"], "FWT": c["FWTABLE"],
                 "TH": c["TAUHFT"], "TH2": c["TAUHFT2"]}
        s, dd, ll, tau = lanes("w3sin4", farrs, {}, dict(sin4_fp, **fp), sin4_ip, ("S", "D", "LL", "TAU"))
        return s[:nspec], dd[:nspec], ll[:nspec], tau[:4]

    # W3SPR4 with CALC_USTAR (W3SPR4.agda): OUT is EMEAN FMEAN FMEAN1 WNMEAN AMAX USTAR Z0 CHARN CD
    # FMEANWS DLWMEAN.
    itaumax, jumax = (int(v) for v in c["spr4int"])
    spr4_fp = dict(zip(("wwnmeanptail", "wwnmeanp", "fte", "ftf", "sstxftftail", "sstxftwn", "deltauw", "delu",
                        "zzwnd", "aalpha", "tauwmax"), c["spr4const"]))
    spr4_fp["tpiinv"] = tpiinv
    spr4_ip = {"nth": nth, "nk": nk, "nspec": nspec, "n11": 11, "itaumax": itaumax, "jumax": jumax}

    def spr4(a, u, tauwx, tauwy, llws):
        farrs = {"A": a, "CG": c["cg"], "WN": c["wn"], "SIG": c["sig"][:nk], "DDEN": c["DDEN"], "ECOS": c["ECOS2"],
                 "ESIN": c["ESIN2"], "LLWS": llws, "TAUT": c["TAUT"]}
        return lanes("w3spr4", farrs, {}, dict(spr4_fp, u=u, tauwx=tauwx, tauwy=tauwy), spr4_ip, ("OUT",))[0][:11]

    # W3SLN1 (W3SLN1.agda).
    slnc1, fspm, fshf = c["sln1const"]

    def sln1(fhigh, ust, usd):
        farrs = {"K": c["wn"], "SIG": c["sig"][:nk], "ECOS": c["ECOS"], "ESIN": c["ESIN"]}
        fp = {"fhigh": fhigh, "ustar": ust, "usdir": usd, "slnc1": slnc1, "fspm": fspm, "fshf": fshf}
        return lanes("w3sln1", farrs, {}, fp, {"nth": nth, "nk": nk, "nspec": nspec}, ("S",))[0][:nspec]

    bad = total = 0

    def check(label, got, ref):
        nonlocal bad, total
        total += 1
        bad += not compare(label, got, ref)

    only = set(args.only.split(",")) if args.only else None

    tables = ("TABU_STRESS", "TABU_TAUHF", "TABU_TAUHF2", "INSIN4")

    def want(r):
        if only:
            return r in only
        return args.srce if r == "W3SRCE" else args.tables if r in tables else True

    if want("W3SNL1"):
        s, dd = snl1(c["A"], cons)
        check("W3SNL1 S (11 launches)", s, c["SNL"])
        check("W3SNL1 D (11 launches)", dd, c["DNL"])
    if want("W3SBT1"):
        s, dd = sbt1(c["A"])
        check("W3SBT1 S", s, c["SBT"])
        check("W3SBT1 D", dd, c["DBT"])
    if want("W3SDB1"):
        s, dd = sdb1(c["A"], _emean, _fmean, _wnmean)
        check("W3SDB1 S", s, c["SDB"])
        check("W3SDB1 D", dd, c["DDB"])
    if want("W3SDS4"):
        s, dd = sds4(c["A"], sds4_fp["ustar"], sds4_fp["usdir"])
        check("W3SDS4 S (7 launches)", s, c["SDS"])
        check("W3SDS4 D (7 launches)", dd, c["DDS"])
    if want("W3SIN4"):
        s, dd, ll, tau = sin4(c["A"])
        check("W3SIN4 S (7 launches)", s, c["SIN"])
        check("W3SIN4 D (7 launches)", dd, c["DIN"])
        check("W3SIN4 LLWS", ll, c["LLWS"])
        check("W3SIN4 TAUWX TAUWY TAUWNX TAUWNY", tau, c["TAUW"])
    if want("W3SPR4"):
        u, _udir, tx, ty = c["SPR4IN"]
        check("W3SPR4 EMEAN ... DLWMEAN (3 launches)", spr4(c["A"], u, tx, ty, c["SPR4LL"]), c["SPR4OUT"])
    if want("W3SLN1"):
        check("W3SLN1 S", sln1(*c["SLN1IN"]), c["SLN"])
    if want("WAVNU1"):
        n1max = int(c["dispint"][0])
        kk, cg = lanes("wavnu1", {"SIG": c["sig"][:nk], "EWN1": c["EWN1"], "ECG1": c["ECG1"]}, {},
                       {"h": depth, "dsie": c["DISP"][0]}, {"nk": nk, "n1max": n1max}, ("K", "CG"))
        check("WAVNU1 K", kk[:nk], c["wn"])
        check("WAVNU1 CG", cg[:nk], c["cg"])
    zz0max, sigmax = c["tabuconst"]
    if want("TABU_STRESS"):
        deltauw, delu, zzwnd, aalpha = spr4_fp["deltauw"], spr4_fp["delu"], spr4_fp["zzwnd"], spr4_fp["aalpha"]
        n = (itaumax + 1) * (jumax + 1)
        got = lanes("tabu_stress", {}, {}, {"deltauw": deltauw, "delu": delu, "aalpha": aalpha, "zz0max": zz0max,
                                            "zzwnd": zzwnd}, {"itaumax": itaumax, "jumax": jumax, "ntaut": n,
                                                              "niter": 10}, ("TAUT",))[0]
        check("TABU_STRESS TAUT", got[:n], c["TAUT"])
    if want("TABU_TAUHF"):
        n = (iustar + 1) * (ialpha + 1)
        got = lanes("tabu_tauhf", {}, {}, {"sigmax": sigmax, "delust": sin4_fp["delust"], "aalpha": sin4_fp["aalpha"],
                                           "bbeta": sin4_fp["bbeta"], "zzalp": sin4_fp["zzalp"], "zz0max": zz0max},
                    {"iustar": iustar, "ialpha": ialpha, "ntab": n, "jtot": 250}, ("TAUHFT",))[0]
        check("TABU_TAUHF TAUHFT", got[:n], c["TAUHFT1"])
    if want("TABU_TAUHF2"):
        # TAUHFT whole, and one plane of TAUHFT2: an entry of plane P folds over the P planes below it.
        n, p = (iustar + 1) * (ialpha + 1), args.plane
        t, t2 = lanes("tabu_tauhf2", {}, {}, {"sigmax": sigmax, "delust": sin4_fp["delust"],
                                              "delalp": sin4_fp["delalp"], "deltail": sin4_fp["deltail"],
                                              "aalpha": sin4_fp["aalpha"], "bbeta": sin4_fp["bbeta"],
                                              "zzalp": sin4_fp["zzalp"]},
                      {"iustar": iustar, "ialpha": ialpha, "ntab": n, "ntab2": n, "jtot": 250, "nplane": p,
                       "base": p * n}, ("TAUHFT", "TAUHFT2"))
        check("TABU_TAUHF2 TAUHFT", t[:n], c["TAUHFT"])
        check(f"TABU_TAUHF2 TAUHFT2 plane {p}", t2[:n], c["TAUHFT2"][p * n:(p + 1) * n])
    if want("INSIN4"):
        # The direction tables and CUMULW that W3SDS4 reads; SDSNTH and DIKCUMUL as WW3 rounded them.
        nsat, _ik1, dik = c["sds4int"]
        sati, satw, cum = lanes("insin4", {"TH": c["TH"], "SIG": c["sig"][:nk], "ECOS": c["ECOS"],
                                           "DSIP": c["DSIP"]}, {},
                                {"ssdsdth": c["sds4case"][1], "ssdscos": c["insin4const"][0],
                                 "ssdsc3": sds4_fp["ssdsc3"], "dth": sds4_fp["dth"]},
                                {"nth": nth, "nk": nk, "nspec": nspec, "nsat": nsat, "sdsnth": c["insin4int"][0],
                                 "dikcumul": dik, "nsat2": nsat * nth, "ncum": nspec * nspec},
                                ("SATI", "SATW", "CUMULW"))
        check("INSIN4 SATINDICES", sati[:nsat * nth], [float(v) for v in c["SATI"]])
        check("INSIN4 SATWEIGHTS", satw[:nsat * nth], c["SATW"])
        check("INSIN4 CUMULW", cum[:nspec * nspec], c["CUMULW"])

    if want("W3SRCE"):
        import srce  # ww3-replay/srce.py: W3SRCE's integration loop on the kernels above
        got, ref = srce.run(c, d, depth, tpiinv, dict(snl1=snl1, sbt1=sbt1, sdb1=sdb1, sds4=sds4, sin4=sin4,
                                                      spr4=spr4, sln1=sln1, lanes=lanes))
        for label, g, r in zip(("W3SRCE SPEC", "W3SRCE scalars"), got, ref):
            check(label, g, r)

    print(f"ww3-replay: {total - bad}/{total} outputs of WW3 agree with the printed kernels "
          f"(sea point {d['isea']}, depth {depth} m, {dev}{', interpreter' if dev == 'cpu' else ''})")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
