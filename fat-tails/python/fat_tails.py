"""Fat-tail diagnostics for equity indexes, after Taleb's
"Statistical Consequences of Fat Tails" (Incerto technical volume, arXiv:2001.10488).

Run from the repo root:

    python3 fat-tails/python/fat_tails.py

Needs numpy, pandas, scipy, matplotlib. Reads fat-tails/data/*.csv and writes
fat-tails/results.json, fat-tails/results.md and fat-tails/figures/*.png.

Educational only. Not investment advice.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
FIG = ROOT / "figures"
RNG = np.random.default_rng(20261101)

# Colors: reference categorical slots 1-3 plus a neutral for reference lines.
C1, C2, C3, GREY = "#2a78d6", "#eb6834", "#1baf7a", "#8a8984"

EWMA_LAMBDA = 0.94  # RiskMetrics daily decay
TAIL_FRACTIONS = (0.01, 0.025, 0.05)
LEVELS = (0.99, 0.999, 0.9999)


# --------------------------------------------------------------------------- data


def load(name: str) -> pd.Series:
    s = pd.read_csv(DATA / f"{name}.csv", parse_dates=["date"]).set_index("date")["close"]
    return np.log(s).diff().dropna()


def ewma_vol(r: pd.Series, lam: float = EWMA_LAMBDA) -> pd.Series:
    """sigma_t estimated with returns up to and including day t."""
    var = np.empty(len(r))
    var[0] = r.iloc[:250].var()
    x = r.to_numpy()
    for t in range(1, len(x)):
        var[t] = lam * var[t - 1] + (1 - lam) * x[t - 1] ** 2
    # var[t] uses x[..t-1]; one more step gives the forecast for t+1
    sig_pred = pd.Series(np.sqrt(var), index=r.index)  # forecast for day t made at t-1
    next_var = lam * var[-1] + (1 - lam) * x[-1] ** 2
    sig_pred.attrs["next"] = float(np.sqrt(next_var))
    return sig_pred


# ------------------------------------------------------------------ the metrics


def hill(x: np.ndarray, k: int) -> float:
    """Hill estimator of the tail exponent alpha from the k largest values of x > 0."""
    xs = np.sort(x)[::-1]
    return 1.0 / (np.mean(np.log(xs[:k])) - np.log(xs[k]))


def hill_path(x: np.ndarray, ks: np.ndarray) -> np.ndarray:
    xs = np.sort(x)[::-1]
    lg = np.log(xs)
    cs = np.cumsum(lg)
    return np.array([1.0 / (cs[k - 1] / k - lg[k]) for k in ks])


def weissman_quantile(x: np.ndarray, k: int, alpha: float, p: float) -> float:
    """Tail quantile at exceedance probability p, extrapolated from the k-th order statistic."""
    xs = np.sort(x)[::-1]
    return float(xs[k] * (k / (len(x) * p)) ** (1.0 / alpha))


def mad_of_sums(x: np.ndarray, n: int) -> float:
    """M(n) = E|S_n - E S_n| over non-overlapping n-day blocks."""
    m = len(x) // n
    s = x[: m * n].reshape(m, n).sum(axis=1)
    return float(np.mean(np.abs(s - s.mean())))


def kappa(x: np.ndarray, n: int, n0: int = 1) -> float:
    """Taleb's kappa_{n0,n} = 2 - (log n - log n0) / log(M(n) / M(n0)).
    0 for the Gaussian, 1 for a Cauchy-like (alpha = 1) process."""
    return 2.0 - (np.log(n) - np.log(n0)) / np.log(mad_of_sums(x, n) / mad_of_sums(x, n0))


def n_equiv(kap: float, n_gauss: int = 30) -> float:
    """Observations needed for the sample mean to shrink as much as a Gaussian's does with
    n_gauss, assuming M(n) ~ n^(1/(2-kappa)): n = n_g^((2-kappa)/(2(1-kappa)))."""
    return n_gauss ** ((2 - kap) / (2 * (1 - kap)))


def ms_ratio(x: np.ndarray, p: int) -> np.ndarray:
    """Running max-to-sum ratio R_n^p = max|X|^p / sum|X|^p. Goes to 0 iff E|X|^p < inf."""
    a = np.abs(x) ** p
    return np.maximum.accumulate(a) / np.cumsum(a)


def kurtosis_report(x: np.ndarray, dates: pd.DatetimeIndex) -> dict:
    a4 = x**4
    order = np.argsort(a4)[::-1]
    yearly = pd.Series(x, index=dates).groupby(dates.year).apply(lambda v: stats.kurtosis(v, fisher=False))
    return {
        "kurtosis": float(stats.kurtosis(x, fisher=False)),
        "kurtosis_without_top_day": float(stats.kurtosis(np.delete(x, order[0]), fisher=False)),
        "kurtosis_without_top_10_days": float(stats.kurtosis(np.delete(x, order[:10]), fisher=False)),
        "share_of_4th_moment_top_day": float(a4[order[0]] / a4.sum()),
        "share_of_4th_moment_top_10_days": float(a4[order[:10]].sum() / a4.sum()),
        "top_day": str(dates[order[0]].date()),
        "yearly_kurtosis_min": float(yearly.min()),
        "yearly_kurtosis_median": float(yearly.median()),
        "yearly_kurtosis_max": float(yearly.max()),
        "yearly_kurtosis_max_year": int(yearly.idxmax()),
    }, yearly


def kappa_null(nobs: int, n: int, kind: str, reps: int = 200, x: np.ndarray | None = None) -> tuple[float, float]:
    vals = []
    for _ in range(reps):
        if kind == "gauss":
            y = RNG.standard_normal(nobs)
        elif kind == "t3":
            y = RNG.standard_t(3, nobs)
        else:  # shuffle: same marginal, no volatility clustering
            y = RNG.permutation(x)
        vals.append(kappa(y, n))
    return float(np.percentile(vals, 5)), float(np.percentile(vals, 95))


# ------------------------------------------------------------------ analysis


def analyse(name: str, r: pd.Series, full: bool) -> tuple[dict, dict]:
    x = r.to_numpy()
    n = len(x)
    sig = ewma_vol(r)
    z = (r / sig).to_numpy()[250:]  # devolatilised residuals, after a 1-year burn-in
    sig_now = sig.attrs["next"]
    sig_1y = float(r.iloc[-252:].std())
    sig_all = float(r.std())

    loss = -x[x < 0]
    zloss = -z[z < 0]
    zabs = np.abs(z)

    out: dict = {"name": name, "first": str(r.index[0].date()), "last": str(r.index[-1].date()), "days": n}
    out["daily_sd_full"] = sig_all
    out["daily_sd_last_year"] = sig_1y
    out["daily_sd_ewma_now"] = sig_now
    out["worst_day"] = float(x.min())
    out["worst_day_date"] = str(r.index[x.argmin()].date())
    out["worst_day_in_full_sample_sigmas"] = float(-x.min() / sig_all)
    out["worst_day_in_ewma_sigmas"] = float(-x.min() / sig.iloc[x.argmin()])

    kr, yearly = kurtosis_report(x, r.index)
    out["kurtosis"] = kr

    # Tail exponent: Hill on raw losses and on devolatilised losses, at several thresholds.
    out["hill_raw_losses"] = {f"{q:.3f}": float(hill(loss, int(q * n))) for q in TAIL_FRACTIONS}
    out["hill_devol_losses"] = {f"{q:.3f}": float(hill(zloss, int(q * len(z)))) for q in TAIL_FRACTIONS}
    out["hill_devol_gains"] = {f"{q:.3f}": float(hill(z[z > 0], int(q * len(z)))) for q in TAIL_FRACTIONS}
    ks_raw = np.arange(20, int(0.10 * n))
    ks_dev = np.arange(20, int(0.10 * len(z)))
    hp_raw = hill_path(loss, ks_raw)
    hp_dev = hill_path(zloss, ks_dev)
    stable = (ks_dev >= int(0.01 * len(z))) & (ks_dev <= int(0.05 * len(z)))
    out["hill_devol_losses_range_1_to_5pct"] = [float(hp_dev[stable].min()), float(hp_dev[stable].max())]
    k_ref = int(0.025 * len(z))
    a_ref = float(hill(zloss, k_ref))
    out["alpha_used"] = a_ref
    out["alpha_se"] = a_ref / np.sqrt(k_ref)

    # MS plot end points.
    out["ms_final"] = {f"p{p}": float(ms_ratio(x, p)[-1]) for p in (1, 2, 3, 4)}

    # Kappa.
    horizons = (2, 10, 30, 100) if full else (2, 10, 30)
    out["kappa"] = {}
    for h in horizons:
        kv = kappa(x, h)
        out["kappa"][f"1,{h}"] = {
            "value": float(kv),
            "gauss_90pct_band": kappa_null(n, h, "gauss"),
            "shuffled_90pct_band": kappa_null(n, h, "shuffle", x=x),
        }
    out["kappa_t3_1_30_band"] = kappa_null(n, 30, "t3") if full else None
    # Aggregation: does summing days make returns Gaussian? Compare with the shuffled series,
    # which keeps the daily marginal but removes volatility clustering.
    shuffled = RNG.permutation(x)
    out["aggregation"] = {}
    for h in (1, 2, 10, 30, 100) if full else (1, 10, 30):
        row = {}
        for tag, v in (("actual", x), ("shuffled", shuffled)):
            m = len(v) // h
            s = v[: m * h].reshape(m, h).sum(axis=1)
            row[f"kurtosis_{tag}"] = float(stats.kurtosis(s, fisher=False))
            row[f"mad_over_sd_{tag}"] = float(np.mean(np.abs(s - s.mean())) / s.std())
        out["aggregation"][str(h)] = row
    k30 = out["kappa"]["1,30"]["value"]
    out["n_needed_to_match_30_gaussian"] = float(n_equiv(k30)) if k30 < 1 else None

    # Gaussian sigma counts: how many days beyond k conditional sigmas vs Gaussian expectation.
    zz = z
    out["exceedances"] = {
        f"{k}sigma": {"observed": int((-zz > k).sum()), "gaussian_expected": float(len(zz) * stats.norm.sf(k))}
        for k in (3, 4, 5, 6)
    }

    # Risk today: one-day loss quantiles and expected shortfall.
    var = {}
    for lvl in LEVELS:
        p = 1 - lvl
        g = stats.norm.ppf(lvl)
        g_es = stats.norm.pdf(g) / p
        q_emp = float(np.quantile(-z, lvl))
        q_evt = weissman_quantile(-z, k_ref, a_ref, p)
        es_evt = q_evt * a_ref / (a_ref - 1)
        var[f"{lvl}"] = {
            "gaussian_var_ewma": float(g * sig_now),
            "gaussian_es_ewma": float(g_es * sig_now),
            "empirical_var_fhs": float(q_emp * sig_now),
            "evt_var_fhs": float(q_evt * sig_now),
            "evt_es_fhs": float(es_evt * sig_now),
            "evt_over_gauss_var": float(q_evt / g),
            "evt_es_over_gauss_es": float(es_evt / g_es),
            "gaussian_var_full_sample": float(g * sig_all),
        }
    out["one_day_risk_now"] = var
    # Gaussian return period of the worst day under full-sample sigma vs the EVT tail of raw losses.
    a_raw = float(hill(loss, int(0.025 * n)))
    worst = -x.min()
    k = int(0.025 * n)
    p_tail = k / n * (worst / np.sort(loss)[::-1][k]) ** (-a_raw)  # P(daily loss > worst)
    out["worst_day_return_period_years"] = {
        "gaussian_full_sigma": float(1 / (stats.norm.sf(worst / sig_all) * 252)),
        "power_law_raw_losses": float(1 / (p_tail * 252)),
        "alpha_raw_2_5pct": a_raw,
    }

    curves = dict(x=x, z=z, loss=loss, zloss=zloss, ks_raw=ks_raw, hp_raw=hp_raw, ks_dev=ks_dev,
                  hp_dev=hp_dev, yearly=yearly, dates=r.index, sig=sig, r=r)
    return out, curves


# ------------------------------------------------------------------ figures


def figures(c: dict, res: dict) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    plt.rcParams.update({"font.size": 10, "axes.spines.top": False, "axes.spines.right": False,
                         "axes.grid": True, "grid.color": "#e4e3df", "grid.linewidth": 0.6,
                         "lines.linewidth": 1.6, "figure.dpi": 130})
    FIG.mkdir(exist_ok=True)

    # 1. MS plot
    fig, axs = plt.subplots(2, 2, figsize=(9, 6), sharex=True)
    for ax, p in zip(axs.flat, (1, 2, 3, 4)):
        ax.plot(np.arange(1, len(c["x"]) + 1), ms_ratio(c["x"], p), color=C1, label="S&P 500")
        ax.plot(np.arange(1, len(c["x"]) + 1), ms_ratio(RNG.standard_normal(len(c["x"])), p), color=GREY,
                label="Gaussian, same n")
        ax.set_title(f"p = {p}:  max|X|^{p} / sum|X|^{p}")
        ax.set_ylim(0, 1)
    axs[0, 0].legend(frameon=False)
    for ax in axs[1]:
        ax.set_xlabel("days since 1950")
    fig.suptitle("MS plot: the ratio goes to 0 only if the p-th moment is finite", fontsize=11)
    fig.tight_layout()
    fig.savefig(FIG / "ms_plot.png")
    plt.close(fig)

    # 2. Hill across thresholds
    fig, ax = plt.subplots(figsize=(8, 4))
    ax.plot(c["ks_raw"] / len(c["x"]) * 100, c["hp_raw"], color=C2, label="raw daily losses")
    ax.plot(c["ks_dev"] / len(c["z"]) * 100, c["hp_dev"], color=C1, label="losses / EWMA vol")
    ax.axhspan(2, 4, color=GREY, alpha=0.08)
    ax.set_xlabel("tail fraction used, % of all days")
    ax.set_ylabel("Hill estimate of alpha")
    ax.set_ylim(1.5, 6)
    ax.legend(frameon=False)
    ax.set_title("Left-tail exponent alpha across thresholds (S&P 500, 1950-2026)")
    fig.tight_layout()
    fig.savefig(FIG / "hill.png")
    plt.close(fig)

    # 3. Zipf plot + mean excess
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(10, 4))
    zl = np.sort(c["zloss"])[::-1]
    surv = np.arange(1, len(zl) + 1) / len(c["z"])
    a1.loglog(zl, surv, ".", ms=3, color=C1, label="S&P 500 losses / EWMA vol")
    g = np.linspace(0.5, zl.max(), 200)
    a1.loglog(g, stats.norm.sf(g), color=GREY, label="Gaussian")
    a1.set_ylim(1 / len(c["z"]) / 3, 1)
    a1.set_xlim(0.5, 20)
    a1.set_xlabel("loss in sigmas (log)")
    a1.set_ylabel("P(L > x) (log)")
    a1.set_title("Zipf plot: a straight line is a power law")
    a1.legend(frameon=False)
    us = np.quantile(zl, np.linspace(0.0, 0.995, 120))
    me = [zl[zl > u].mean() - u for u in us]
    a2.plot(us, me, color=C1, label="S&P 500")
    gz = RNG.standard_normal(len(c["z"]))
    gl = -gz[gz < 0]
    ug = np.quantile(gl, np.linspace(0.0, 0.995, 120))
    a2.plot(ug, [gl[gl > u].mean() - u for u in ug], color=GREY, label="Gaussian")
    a2.set_xlabel("threshold u (sigmas)")
    a2.set_ylabel("E[L - u | L > u]")
    a2.set_title("Mean excess: rising = power law, falling = thin tail")
    a2.legend(frameon=False)
    fig.tight_layout()
    fig.savefig(FIG / "zipf_mean_excess.png")
    plt.close(fig)

    # 4. Kurtosis instability
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(10, 4))
    y = c["yearly"]
    a1.bar(y.index, y.values, color=C1, width=0.8)
    a1.axhline(3, color=GREY, lw=1)
    a1.text(1992, 40, "grey line: Gaussian = 3", color="#52514e", fontsize=8)
    a1.set_title("Kurtosis, year by year")
    run = pd.Series([stats.kurtosis(c["x"][:i], fisher=False) for i in range(500, len(c["x"]), 20)],
                    index=c["dates"][500::20])
    a2.plot(run.index, run.values, color=C1)
    a2.set_title("Kurtosis of the whole history so far")
    a2.axhline(3, color=GREY, lw=1)
    a2.set_ylim(0, None)
    fig.tight_layout()
    fig.savefig(FIG / "kurtosis.png")
    plt.close(fig)

    # 5. Kappa vs horizon
    fig, ax = plt.subplots(figsize=(7, 4))
    hs = [2, 5, 10, 20, 30, 50, 100]
    ax.plot(hs, [kappa(c["x"], h) for h in hs], "o-", color=C1, label="S&P 500 daily log returns")
    ax.plot(hs, [np.mean([kappa(RNG.permutation(c["x"]), h) for _ in range(40)]) for h in hs], "o-",
            color=C3, label="same returns, shuffled")
    ax.plot(hs, [np.mean([kappa(RNG.standard_t(3, len(c["x"])), h) for _ in range(40)]) for h in hs], "o--",
            color=C2, label="Student t, alpha = 3")
    ax.axhline(0, color=GREY, lw=1)
    ax.text(2, 0.02, "Gaussian", color="#52514e", fontsize=8)
    ax.set_xscale("log")
    ax.set_xlabel("n (days summed)")
    ax.set_ylabel("kappa(1, n)")
    ax.set_title("Taleb's kappa: distance from the Gaussian basin")
    ax.legend(frameon=False)
    fig.tight_layout()
    fig.savefig(FIG / "kappa.png")
    plt.close(fig)


# ------------------------------------------------------------------ report


def pct(v: float) -> str:
    return f"{100 * v:.2f}%"


def markdown(all_res: list[dict]) -> str:
    sp = all_res[0]
    L = ["# Results", "", f"Data through {sp['last']}. Generated by `fat-tails/python/fat_tails.py`.", ""]
    L += ["## One-day loss at today's volatility (S&P 500)", "",
          f"EWMA daily sigma for the next day: {pct(sp['daily_sd_ewma_now'])} "
          f"(last year: {pct(sp['daily_sd_last_year'])}, since 1950: {pct(sp['daily_sd_full'])}).", "",
          "| level | Gaussian VaR | EVT VaR | ratio | Gaussian ES | EVT ES | ratio |", "|---|---|---|---|---|---|---|"]
    for lvl, v in sp["one_day_risk_now"].items():
        L.append(f"| {float(lvl):.2%} | {pct(v['gaussian_var_ewma'])} | {pct(v['evt_var_fhs'])} | "
                 f"{v['evt_over_gauss_var']:.2f}x | {pct(v['gaussian_es_ewma'])} | {pct(v['evt_es_fhs'])} | "
                 f"{v['evt_es_over_gauss_es']:.2f}x |")
    L += ["", "## Index comparison", "",
          "| index | window | kurtosis | top day share of 4th moment | alpha (devol, 2.5%) | kappa(1,10) | kappa(1,30) | EWMA sigma now | 99.9% VaR Gauss / EVT |",
          "|---|---|---|---|---|---|---|---|---|"]
    for r in all_res:
        v = r["one_day_risk_now"]["0.999"]
        L.append(f"| {r['name']} | {r['first'][:4]}-{r['last'][:4]} | {r['kurtosis']['kurtosis']:.1f} | "
                 f"{pct(r['kurtosis']['share_of_4th_moment_top_day'])} | {r['alpha_used']:.2f} ± {r['alpha_se']:.2f} | "
                 f"{r['kappa']['1,10']['value']:.2f} | {r['kappa']['1,30']['value']:.2f} | {pct(r['daily_sd_ewma_now'])} | "
                 f"{pct(v['gaussian_var_ewma'])} / {pct(v['evt_var_fhs'])} |")
    L += ["", "## Summing days does not make S&P 500 returns Gaussian", "",
          "Gaussian: kurtosis 3, MAD/SD 0.798. 'Shuffled' keeps the daily returns but destroys volatility clustering.", "",
          "| days summed | kurtosis | kurtosis, shuffled | MAD/SD | MAD/SD, shuffled | kappa(1,n) |", "|---|---|---|---|---|---|"]
    for h, a in sp["aggregation"].items():
        kv = sp["kappa"].get(f"1,{h}", {}).get("value")
        L.append(f"| {h} | {a['kurtosis_actual']:.1f} | {a['kurtosis_shuffled']:.1f} | {a['mad_over_sd_actual']:.3f} | "
                 f"{a['mad_over_sd_shuffled']:.3f} | {'' if kv is None else f'{kv:.2f}'} |")
    L += ["", "## Gaussian 'impossible' days (S&P 500, loss / EWMA sigma, 1951-2026)", "",
          "| beyond | observed | Gaussian expects |", "|---|---|---|"]
    for k, e in sp["exceedances"].items():
        L.append(f"| {k} | {e['observed']} | {e['gaussian_expected']:.3g} |")
    return "\n".join(L) + "\n"


def main() -> None:
    sp = load("sp500")
    res_sp, curves = analyse("S&P 500", sp, full=True)
    res = [res_sp]
    res.append(analyse("S&P 500 (2015+)", sp[sp.index >= "2015-01-01"], full=False)[0])
    for name, f in (("Nasdaq 100", "ndx"), ("Nikkei 225", "n225")):
        res.append(analyse(name, load(f), full=False)[0])
    figures(curves, res_sp)

    def clean(o):
        if isinstance(o, dict):
            return {k: clean(v) for k, v in o.items() if v is not None}
        if isinstance(o, (list, tuple)):
            return [clean(v) for v in o]
        if isinstance(o, (np.floating, np.integer)):
            return o.item()
        return o

    (ROOT / "results.json").write_text(json.dumps(clean(res), indent=2) + "\n")
    (ROOT / "results.md").write_text(markdown(res))
    print(markdown(res))


if __name__ == "__main__":
    main()
