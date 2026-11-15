"""WAVEWATCH III's W3SRCE at one sea point, replayed on the printed kernels: the integration loop
of w3srcemd.F90 (srce_direct, IT /= 0, the switch of ww3_ts1, ST4 NL1 BT1 DB1 LN1 without ice), with every
source term, the step, the tail, the means and the fluxes computed by a kernel, and the loop
itself (how many passes, when it ends) run here on the host, as W3SRCE runs it on the CPU.

    replay.py GATHER.py CAPTURE.txt --srce

The host computes only what W3SRCE computes between the calls, in float32 as gfortran -O3 does
(numpy's float32 is IEEE single, each operation rounded; EXPF is glibc's, called through
ctypes):

    :1124-1179  TWS = 1./FMEANWS ; SPECINIT = SPEC ; USTAR = MAX(0.001, USTAR)
                FHIGH = MAX((FFXFM + 0.)*MAX(FMEAN1, FMEANWS), FFXPM/USTAR)
    W3SNL1      KDMEAN = WNMEAN*DEPTH and CONS (w3snl1md.F90:324-326), the order of its GIMPLE:
                X = MAX(KDCON*KDMEAN, KDMN) ; CONS = SNLC1*((SNLS1/X)*(1.-SNLS2*X)*EXPF(MAX(SNLS3*X, -1E15)) + 1.)
    :1891       USTAR = MAX(0.001, USTAR) after W3SPR4
    :1982       the exit, DTTOT >= 0.9999*DTG

Everything else, DT included, comes from a kernel: srce_step's DTB lanes are DT, SHAVE, the new
DTTOT and the DT that DTDYN sums; srce_tail's FT lanes are the new FHIGH and NKH.
"""

import ctypes

import numpy as np

F = np.float32
_libm = ctypes.CDLL("libm.so.6")
_libm.expf.restype = ctypes.c_float
_libm.expf.argtypes = [ctypes.c_float]


def expf(x):
    return F(_libm.expf(F(x)))


def run(c, d, depth, tpiinv, k):
    """Run the loop; return ([SPEC, scalars], [WW3's SPEC, WW3's scalars])."""
    nth, nk, nspec = d["nth"], d["nk"], d["nspec"]
    (dtmax, xflt, xrel, dtmin, facti1, facti2, facp, ffxfa, ffxfm, ffxpm, fachfa, tpi, grav, _tpiinv,
     dair, _dwat) = (F(v) for v in c["srceconst"])
    kdcon, kdmn, snlc1, snls1, snls2, snls3 = (F(v) for v in c["snlconst"])
    u10, u10dir, dtg, coef = (F(v) for v in c["SRCEIN"])
    drat = F(dair / F(1000.0))
    sig = c["sig"][:nk]
    lanes = k["lanes"]

    def sin4(a, ust, z0):
        return k["sin4"](a, u=float(u10), ustar=float(ust), usdir=float(u10dir), z0=float(z0), drat=float(drat))

    def spr4(a, tauwx, tauwy, llws):
        o = k["spr4"](a, float(u10), float(tauwx), float(tauwy), llws)
        return dict(zip(("emean", "fmean", "fmean1", "wnmean", "amax", "ustar", "z0", "charn", "cd", "fmeanws",
                         "dlwmean"), (F(v) for v in o)))

    spec = list(c["A"])
    # :1055-1062, IT /= 0: W3SPR4 with the stress at zero, W3SIN4, W3SPR4 again.
    m = spr4(spec, 0.0, 0.0, [1.0] * nspec)
    _s, _d, llws, tau = sin4(spec, m["ustar"], m["z0"])
    tauwx, tauwy, tauwax, tauway = (F(v) for v in tau)
    m = spr4(spec, tauwx, tauwy, llws)
    tws = F(F(1.0) / m["fmeanws"])
    specinit = list(spec)
    ust = max(F(0.001), m["ustar"])
    fhigh = max(F(ffxfm + F(0.0)) * max(m["fmean1"], m["fmeanws"]), F(ffxpm / ust))

    dttot = F(0.0)
    dtdyn = F(0.0)
    nsteps = 0
    phiaw = phibbl = tauwix = tauwiy = tauwnx = tauwny = F(0.0)
    wc3 = F(0.0)
    step_ip = {"nth": nth, "nk": nk, "nspec": nspec, "n4": 4}
    # The W3SIN4 that ends a pass (:1975) and the one that starts the next (:1236) see the same
    # spectrum, USTAR and Z0, so the second is the first's result, not a second run.
    after = None
    while True:
        nsteps += 1
        vsln = k["sln1"](float(fhigh), float(ust), float(u10dir))
        vsin, vdin, llws, tau = after or sin4(spec, ust, m["z0"])
        tauwx, tauwy, tauwax, tauway = (F(v) for v in tau)
        x = max(F(kdcon * F(m["wnmean"] * F(depth))), kdmn)
        cons = F(snlc1 * F(F(F(snls1 / x) * F(F(1.0) - F(snls2 * x))) * expf(max(F(snls3 * x), F(-1e15))) + F(1.0)))
        vsnl, vdnl = k["snl1"](spec, float(cons))
        vsds, vdds = k["sds4"](spec, float(ust), float(u10dir))
        vsdb, vddb = k["sdb1"](spec, float(m["emean"]), float(m["fmean"]), float(m["wnmean"]))
        vsbt, vdbt = k["sbt1"](spec)
        farrs = {"A": spec, "SPECINIT": specinit, "VSLN": vsln, "VSIN": vsin, "VDIN": vdin, "VSNL": vsnl,
                 "VDNL": vdnl, "VSDS": vsds, "VDDS": vdds, "VSBT": vsbt, "VDBT": vdbt, "VSDB": vsdb, "VDDB": vddb,
                 "WN": c["wn"], "SIG": sig}
        fp = {"dtg": dtg, "dttot": dttot, "dtmax": dtmax, "xflt": xflt, "amax": m["amax"], "xrel": xrel,
              "dtmin": dtmin, "fhigh": fhigh, "facti1": facti1, "facti2": facti2, "facp": facp}
        dtb, new = lanes("w3srce_step", farrs, {}, fp, step_ip, ("DTB", "SPEC"))
        dt, _shave, dttot, dtsum = (F(v) for v in dtb[:4])
        dtdyn = F(dtdyn + dtsum)
        spec = new[:nspec]
        fx = lanes("w3srce_pass", {"SPEC": spec, "VSIN": vsin, "VDIN": vdin, "VSBT": vsbt, "VDBT": vdbt,
                                    "DDEN": c["DDEN"], "CG": c["cg"]}, {},
                   {"dt": dt, "phiaw": phiaw, "phibbl": phibbl, "tauwix": tauwix, "tauwiy": tauwiy,
                    "tauwnx": tauwnx, "tauwny": tauwny, "tauwx": tauwx, "tauwy": tauwy, "tauwax": tauwax,
                    "tauway": tauway, "dair": dair}, {"nth": nth, "nk": nk, "nspec": nspec, "n7": 7}, ("FX",))[0]
        phiaw, phibbl, wc3, tauwix, tauwiy, tauwnx, tauwny = (F(v) for v in fx[:7])
        m = spr4(spec, tauwx, tauwy, llws)
        ust = max(F(0.001), m["ustar"])
        fp = {"u10": u10, "fmeanws": m["fmeanws"], "fmean1": m["fmean1"], "ustar": ust, "ffxfa": ffxfa,
              "ffxfm": ffxfm, "ffxpm": ffxpm, "facti1": facti1, "facti2": facti2, "fachfa": fachfa, "tpi": tpi,
              "grav": grav, "fhigh0": fhigh}
        ft, new = lanes("w3srce_tail", {"A": spec, "SIG": sig}, {}, fp,
                        {"nth": nth, "nk": nk, "nspec": nspec, "n2": 2}, ("FT", "SPEC"))
        fhigh = F(ft[0])
        spec = new[:nspec]
        after = sin4(spec, ust, m["z0"])
        tauwx, tauwy, tauwax, tauway = (F(v) for v in after[3])
        print(f"  W3SRCE pass {nsteps}: DT {float(dt):.3f} s, DTTOT {float(dttot):.3f} s, FHIGH {float(fhigh):.5f}, "
              f"NKH {int(ft[1])}", flush=True)
        if dttot >= F(F(0.9999) * dtg):
            break
        if nsteps > 1000:
            raise RuntimeError("W3SRCE did not end in 1000 passes")

    fp = {"dtg": dtg, "tauwix": tauwix, "tauwiy": tauwiy, "tauwnx": tauwnx, "tauwny": tauwny, "taubbl1": 0.0,
          "taubbl2": 0.0, "phiaw": phiaw, "phibbl": phibbl, "dair": dair, "coef": coef, "ustar": ust,
          "ustdir": u10dir, "dtdyn": dtdyn, "fhigh": fhigh, "tpiinv": tpiinv}
    fx = lanes("w3srce_end", {"SPECINIT": specinit, "SPEC": spec, "ECOS": c["ECOS"], "ESIN": c["ESIN"],
                               "DDEN": c["DDEN"], "CG": c["cg"], "WN": c["wn"], "SIG": sig}, {}, fp,
               {"nth": nth, "nk": nk, "nspec": nspec, "nsteps": nsteps, "n15": 15}, ("FX",))[0]
    (tauox, tauoy, tauwix, tauwiy, tauwnx, tauwny, _tb1, _tb2, tauocx, tauocy, phioc, phiaw, phibbl,
     dtdyn, fcut) = fx[:15]
    spec = [max(0.0, v) for v in spec]
    # The order of SRCEOUT in ww3_capture.F90.
    got = [dtdyn, fcut, ust, u10dir, tauwx, tauwy, tauox, tauoy, tauwix, tauwiy, tauwnx, tauwny, phiaw,
           m["charn"], tws, phioc, phibbl, tauocx, tauocy, m["wnmean"], wc3]
    return [spec, [float(v) for v in got]], [c["SRCE"], c["SRCEOUT"]]
