"""Measure the additive joint step of agda/src/TvAudience/Joint.agda on the simulated test set.

For each slot the rows are the three channels and the outside audience (the pool minus the
channels). Each row has an independent forecast: a channel model (XGBoost, XGBoost + rivals or the MLP
of experiment.py) for the channels,
and the "other" XGBoost model of experiment.py for the
outside row. The joint step moves every forecast of the slot by the same amount, so that they add
up to the pool forecast p:

    f'_i = f_i - (sum f - p) / C

Joint.agda proves C * (SSE_alone - SSE_joint) = S^2 - eps^2, with S = sum f - T and eps = p - T,
so the step gains exactly on the slots where |eps| <= |S|. This script counts those slots, checks
the identity on Double, and reports SSE and WAPE before and after, for two groupings (the channels with the
outside row, and the channels alone) and two totals (a forecast, and the actual total: an oracle,
eps = 0).

It reuses experiment.py's functions and seed, so the forecasts are the ones of results.json; it
writes tv-audience/joint_step.json and tv-audience/joint_step.md and changes nothing else.

    nix develop .#tv-joint --command python3 tv-audience/python/joint_step.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
import experiment as ex  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MODELS = {"xgb": "XGBoost", "xgb_rival": "XGBoost + rivals", "dnn": "DNN (MLP)"}


def joint_step(te: pd.DataFrame, chan_hat: np.ndarray, other_hat: np.ndarray, p_slot: np.ndarray,
               outside: bool) -> dict:
    """With outside=True the rows are the channels and the outside audience, and p is the pool
    forecast. With outside=False the rows are the channels alone, and p is the pool forecast minus
    the outside forecast (or, for the oracle, the actual sum of the channels)."""
    sid = ex._slot_index(te)
    n = sid.max() + 1
    y = te.audience.to_numpy()
    first = te.groupby(sid).first()
    y_out = (first.pool * first.outside).to_numpy()          # actual outside audience per slot
    f_out = pd.Series(other_hat).groupby(sid).first().to_numpy()
    w = 1.0 if outside else 0.0                               # the outside row is in the group or not
    C = np.bincount(sid).astype(float) + w
    T = np.bincount(sid, weights=y) + w * y_out
    F = np.bincount(sid, weights=chan_hat) + w * f_out
    S, eps = F - T, p_slot - T
    k = (F - p_slot) / C
    chan_j, out_j = chan_hat - k[sid], f_out - k
    sse_ch_a = np.bincount(sid, weights=(chan_hat - y) ** 2)
    sse_ch_j = np.bincount(sid, weights=(chan_j - y) ** 2)
    sse_a = sse_ch_a + w * (f_out - y_out) ** 2
    sse_j = sse_ch_j + w * (out_j - y_out) ** 2
    lhs, rhs = C * (sse_a - sse_j), S ** 2 - eps ** 2
    ident = float(np.max(np.abs(lhs - rhs) / np.maximum(np.abs(rhs), 1.0)))
    cond = np.abs(eps) <= np.abs(S)
    gained = sse_j <= sse_a
    masks = {"all": np.ones(len(te), bool), "big_show": te.big_show.to_numpy(),
             "clash": (te.big_show & (te.rival_big | (te.n_same_genre > 0))).to_numpy()}
    big_slot = np.bincount(sid, weights=te.big_show.to_numpy().astype(float)) > 0
    out = {
        "slots": int(n),
        "identity_max_rel_err": ident,
        "cond_share_all": float(cond.mean()),
        "cond_share_big_slots": float(cond[big_slot].mean()),
        "cond_implies_gain": bool(np.all(gained[cond])),
        "gain_share_all": float(gained.mean()),
        "sse_alone": float(sse_a.sum()), "sse_joint": float(sse_j.sum()),
        "sse_alone_big_slots": float(sse_a[big_slot].sum()), "sse_joint_big_slots": float(sse_j[big_slot].sum()),
        "sse_alone_cond_slots": float(sse_a[cond].sum()), "sse_joint_cond_slots": float(sse_j[cond].sum()),
        "sse_channels_alone": float(sse_ch_a.sum()), "sse_channels_joint": float(sse_ch_j.sum()),
        "negative_forecasts": int((chan_j < 0).sum()),
        "big_slots": int(big_slot.sum()),
    }
    for mk, m in masks.items():
        out[f"wape_alone_{mk}"] = ex.wape(y[m], chan_hat[m])
        out[f"wape_joint_{mk}"] = ex.wape(y[m], chan_j[m])
    return out


def main():
    rng = np.random.default_rng(ex.SEED)
    df = ex.build_features(ex.simulate(seed=ex.SEED), rng)
    tr, te = df[df.date < ex.TEST_START].reset_index(drop=True), df[df.date >= ex.TEST_START].reset_index(drop=True)
    ytr = tr.log_aud - tr.lag_mean
    Xtr = ex.design(tr, False); Xte = ex.design(te, False).reindex(columns=Xtr.columns, fill_value=0)
    Xtr_r = ex.design(tr, True); Xte_r = ex.design(te, True).reindex(columns=Xtr_r.columns, fill_value=0)
    chan = {"xgb": np.exp(te.lag_mean + ex.fit_xgb(Xtr, ytr, Xte)).to_numpy(),
            "xgb_rival": np.exp(te.lag_mean + ex.fit_xgb(Xtr_r, ytr, Xte_r)).to_numpy(),
            "dnn": np.exp(te.lag_mean + ex.fit_dnn(Xtr, ytr, Xte)).to_numpy()}
    pool_hat = ex.fit_pool(tr, te)

    # The outside row's forecast, as experiment.py builds it for MinT.
    tr_o = tr.groupby(["market", "date", "slot"]).first().reset_index()
    te_o = te.groupby(["market", "date", "slot"]).first().reset_index()
    tr_o["other"] = np.log(tr_o.pool * tr_o.outside)
    Xo_tr = pd.concat([tr_o[ex.POOL_NUM].astype(float), pd.get_dummies(tr_o.market, dtype=float)], axis=1)
    Xo_te = pd.concat([te_o[ex.POOL_NUM].astype(float), pd.get_dummies(te_o.market, dtype=float)], axis=1)
    te_o["other_hat"] = np.exp(te_o.pool_lag_mean + ex.fit_xgb(Xo_tr, tr_o.other - tr_o.pool_lag_mean, Xo_te))
    other_hat = te.join(te_o.set_index(["market", "date", "slot"]).other_hat,
                        on=["market", "date", "slot"]).other_hat.to_numpy()

    sid = ex._slot_index(te)
    p_model = pd.Series(pool_hat).groupby(sid).first().to_numpy()
    p_true = te.groupby(sid).pool.first().to_numpy()
    f_out = pd.Series(other_hat).groupby(sid).first().to_numpy()
    ch_true = np.bincount(sid, weights=te.audience.to_numpy())
    res = {}
    for name, f in chan.items():
        res[name] = {"outside_pool_model": joint_step(te, f, other_hat, p_model, True),
                     "outside_pool_actual": joint_step(te, f, other_hat, p_true, True),
                     "channels_pool_model": joint_step(te, f, other_hat, p_model - f_out, False),
                     "channels_pool_actual": joint_step(te, f, other_hat, ch_true, False)}
    (ROOT / "joint_step.json").write_text(json.dumps({"seed": ex.SEED, "results": res}, indent=2))
    write_md(res)
    print(json.dumps(res, indent=1))


def pct(x):
    return f"{100 * x:.1f}%"


VARIANTS = (("outside_pool_model", "channels + outside", "pool model"),
            ("outside_pool_actual", "channels + outside", "actual pool"),
            ("channels_pool_model", "channels", "pool model − outside model"),
            ("channels_pool_actual", "channels", "actual channel total"))


def write_md(res):
    r0 = res["xgb"]["outside_pool_model"]
    lines = [
        "# The additive joint step on the simulated test set",
        "",
        "Generated by `python3 tv-audience/python/joint_step.py`. Synthetic data only. The rows of a slot",
        "are its three channels and, in the first grouping, the outside audience; p is the forecast of",
        "their total. The theorem is `joint-gain` of `agda/src/TvAudience/Joint.agda`. SSE is in squared",
        "millions of viewers; WAPE is over the channel rows only, as in `results.md`.",
        "",
        f"Test: {r0['slots']} slots, {r0['big_slots']} with a big show.",
        "",
        "| Channel model | Rows | p | \\|ε\\| ≤ \\|S\\| (all slots) | (big-show slots) | SSE joint / alone, all rows | "
        "SSE joint / alone, channels | SSE joint / alone, big-show slots | WAPE all, alone → joint | WAPE big shows | WAPE contested | Identity rel. error |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for name, label in MODELS.items():
        for pk, rows, plabel in VARIANTS:
            r = res[name][pk]
            lines.append(
                f"| {label} | {rows} | {plabel} | {pct(r['cond_share_all'])} | {pct(r['cond_share_big_slots'])} | "
                f"{r['sse_joint'] / r['sse_alone']:.3f} | {r['sse_channels_joint'] / r['sse_channels_alone']:.3f} | "
                f"{r['sse_joint_big_slots'] / r['sse_alone_big_slots']:.3f} | "
                f"{pct(r['wape_alone_all'])} → {pct(r['wape_joint_all'])} | "
                f"{pct(r['wape_alone_big_show'])} → {pct(r['wape_joint_big_show'])} | "
                f"{pct(r['wape_alone_clash'])} → {pct(r['wape_joint_clash'])} | {r['identity_max_rel_err']:.1e} |")
    lines += ["", "On every row, each slot with |ε| ≤ |S| has SSE joint ≤ SSE alone: "
              + ("yes." if all(res[m][v[0]]["cond_implies_gain"] for m in MODELS for v in VARIANTS)
                 else "NO (see joint_step.json).")]
    ref = json.loads((ROOT / "results.json").read_text())["results"]
    lines += ["", "Reproduction: the WAPE of each channel model alone, here and in `results.json` (all, big shows, contested):", ""]
    for name, label in MODELS.items():
        r, q = res[name]["outside_pool_model"], ref[name]
        lines.append(f"- {label}: {pct(r['wape_alone_all'])}, {pct(r['wape_alone_big_show'])}, {pct(r['wape_alone_clash'])}"
                     f" here; {pct(q['wape_all'])}, {pct(q['wape_big_show'])}, {pct(q['wape_clash'])} in results.json.")
    (ROOT / "joint_step.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    if sys.argv[1:] == ["--md"]:  # rewrite joint_step.md from joint_step.json, with no training
        write_md(json.loads((ROOT / "joint_step.json").read_text())["results"])
    else:
        main()
