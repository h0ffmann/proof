"""Compare audience forecasters on simulated prime-time TV data (see simulate.py).

Models
  xgb        XGBoost, one row per channel and slot, own features only
  xgb_rival  XGBoost with the rivals' line-up features added (ablation)
  dnn        multilayer perceptron (scikit-learn), own features only
  timestral  Mistral's Timestral time-series foundation model, zero-shot (needs torch + HF weights)
  jcs        Joint Competitive Share model: slot viewing pool x multinomial-logit shares
  ns_jcs     neurosymbolic JCS: a neural utility inside the same symbolic share structure
  xgb_mint   xgb_rival forecasts reconciled with Nixtla HierarchicalForecast (MinTrace, WLS structural)

Every forecast is made 7 days ahead: features use only line-ups (known in advance) and audiences at
least 7 days old. Train: 2023-02-06 to 2025-12-31. Test: 2026-01-01 to 2026-10-31.

Writes tv-audience/results.json, tv-audience/results.md and tv-audience/figures/*.png.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from simulate import GENRES, EPISODE_TYPES, simulate  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
FIG = ROOT / "figures"
SEED = 20261107
TEST_START = pd.Timestamp("2026-01-01")
TRAIN_START = pd.Timestamp("2023-02-06")
HORIZON = 7


# ----------------------------------------------------------------------------- features

def build_features(df: pd.DataFrame, rng: np.random.Generator) -> pd.DataFrame:
    df = df.sort_values(["market", "slot", "date", "ch_idx"]).reset_index(drop=True)
    # The panel measures total TV-set usage per slot (the pool) with a small error.
    pool = (df.groupby(["market", "date", "slot"]).true_pool.first()
            * np.exp(rng.normal(0, 0.02, df.groupby(["market", "date", "slot"]).ngroups)))
    df = df.join(pool.rename("pool"), on=["market", "date", "slot"])
    df["share"] = df.audience / df.pool
    df["log_aud"] = np.log(df.audience)

    key = ["market", "channel", "slot"]
    g = df.groupby(key)
    for k in (7, 14, 21, 28):
        df[f"lag{k}"] = g.log_aud.shift(k)
    df["lag_mean"] = df[["lag7", "lag14", "lag21", "lag28"]].mean(axis=1)
    df["lag_series_change"] = (g.series.shift(7) != df.series).astype(float)
    # Last audience of the same series at least HORIZON days before (NaN for a new series).
    df["series_lag"] = np.nan
    for _, idx in df.groupby(["market", "series"]).groups.items():
        sub = df.loc[idx, ["date", "log_aud"]].sort_values("date")
        known = sub.copy()
        known["date"] = known.date + pd.Timedelta(days=HORIZON)
        m = pd.merge_asof(sub[["date"]].reset_index(), known.rename(columns={"log_aud": "sl"}),
                          on="date", direction="backward")
        df.loc[m["index"], "series_lag"] = m.sl.values

    # Slot-level history: pool and each channel's share (logit against the outside option).
    slot = df.groupby(["market", "slot", "date"]).agg(pool=("pool", "first"), inside=("share", "sum"))
    slot["log_pool"] = np.log(slot.pool)
    gs = slot.groupby(level=[0, 1])
    for k in (7, 14, 21, 28):
        slot[f"pool_lag{k}"] = gs.log_pool.shift(k)
    slot["pool_lag_mean"] = slot[[f"pool_lag{k}" for k in (7, 14, 21, 28)]].mean(axis=1)
    slot["outside"] = (1 - slot.inside).clip(lower=0.02)
    df = df.join(slot[["pool_lag7", "pool_lag_mean", "outside"]], on=["market", "slot", "date"])
    df["logodds"] = np.log(df.share) - np.log(df.outside)
    g = df.groupby(key)
    df["lo_lag7"] = g.logodds.shift(7)
    df["lo_lag_mean"] = (g.logodds.shift(7) + g.logodds.shift(14) + g.logodds.shift(21)
                         + g.logodds.shift(28)) / 4

    # Rival line-up (known a week ahead in published schedules).
    grp = df.groupby(["market", "date", "slot"])
    df["n_same_genre"] = grp.genre.transform(lambda s: s.map(s.value_counts())) - 1
    df["slot_max_hype"] = grp.hype.transform("max")
    df["slot_sum_hype"] = grp.hype.transform("sum")
    df["rival_sum_hype"] = df.slot_sum_hype - df.hype
    df["rival_max_hype"] = grp.hype.transform(lambda s: _rival_max(s.values))
    df["rival_lag_sum"] = grp.lag7.transform(lambda s: np.log(np.exp(s).sum())) - df.lag7
    df["rival_big"] = (df.groupby(["market", "date", "slot"]).big_show.transform("sum")
                       - df.big_show.astype(int)) > 0

    df["dow"] = df.date.dt.day_of_week
    df["month"] = df.date.dt.month
    doy = df.date.dt.day_of_year
    df["doy_sin"] = np.sin(2 * np.pi * doy / 365.25)
    df["doy_cos"] = np.cos(2 * np.pi * doy / 365.25)
    df["t"] = (df.date - df.date.min()).dt.days / 365.25
    df["holiday"] = (((df.date.dt.month == 12) & (df.date.dt.day >= 24))
                     | ((df.date.dt.month == 1) & (df.date.dt.day == 1))).astype(float)
    df["log1p_hype"] = np.log1p(df.hype)
    df = df[df.date >= TRAIN_START].reset_index(drop=True)
    return df


def _rival_max(h: np.ndarray) -> np.ndarray:
    out = np.empty_like(h)
    for i in range(len(h)):
        out[i] = np.delete(h, i).max() if len(h) > 1 else 0.0
    return out


OWN_NUM = ["hype", "log1p_hype", "lag7", "lag14", "lag21", "lag28", "lag_mean", "series_lag",
           "lag_series_change", "dow", "doy_sin", "doy_cos", "holiday", "slot_idx"]
RIVAL_NUM = ["n_same_genre", "rival_sum_hype", "rival_max_hype", "rival_lag_sum", "pool_lag7",
             "pool_lag_mean"]
CATS = ["market", "channel", "genre", "episode_type"]


def design(df: pd.DataFrame, rival: bool) -> pd.DataFrame:
    num = OWN_NUM + (RIVAL_NUM if rival else [])
    X = pd.get_dummies(df[CATS].astype("category"), dtype=float)
    X = pd.concat([df[num].astype(float), X], axis=1)
    return X


# ----------------------------------------------------------------------------- models

def fit_xgb(Xtr, ytr, Xte, seed=SEED):
    import xgboost as xgb
    m = xgb.XGBRegressor(n_estimators=600, learning_rate=0.03, max_depth=6, subsample=0.8,
                         colsample_bytree=0.8, min_child_weight=10, reg_lambda=5.0, random_state=seed, n_jobs=4)
    m.fit(Xtr, ytr)
    return m.predict(Xte)


def fit_dnn(Xtr, ytr, Xte, seed=SEED):
    from sklearn.neural_network import MLPRegressor
    from sklearn.preprocessing import StandardScaler
    Xtr = Xtr.fillna(Xtr.median()); Xte = Xte.fillna(Xtr.median())
    sx = StandardScaler().fit(Xtr)
    mu, sd = ytr.mean(), ytr.std()
    m = MLPRegressor(hidden_layer_sizes=(128, 64, 32), alpha=1e-3, learning_rate_init=1e-3,
                     batch_size=256, max_iter=300, early_stopping=True, n_iter_no_change=15,
                     random_state=seed)
    m.fit(sx.transform(Xtr), (ytr - mu) / sd)
    return m.predict(sx.transform(Xte)) * sd + mu


# --- Joint Competitive Share (JCS) model --------------------------------------------------------
#
# For slot j (market, date, hour) with channels c = 1..C and an outside option 0:
#   audience_cj = pool_j * s_cj,   s_cj = exp(u_cj) / (1 + sum_k exp(u_kj)),   u_0j = 0
# The pool is forecast by its own model; the utilities u_cj depend on the channel's programme and on
# its rivals' programmes in the same slot, so the C forecasts of a slot are made jointly and can
# never add up to more viewers than the pool.

SHARE_NUM = ["log1p_hype", "lo_lag7", "lo_lag_mean", "n_same_genre", "rival_max_hype",
             "rival_sum_hype", "lag_series_change", "t", "holiday"]


def share_design(df: pd.DataFrame) -> np.ndarray:
    parts = [df[SHARE_NUM].fillna(0.0).to_numpy(float)]
    parts.append(pd.get_dummies(df.channel, dtype=float).to_numpy())          # brand
    gs = df.genre + "@" + df.slot_idx.astype(str)
    parts.append(pd.get_dummies(gs, dtype=float).reindex(
        columns=[f"{g}@{s}" for g in GENRES for s in range(3)], fill_value=0.0).to_numpy())
    parts.append(pd.get_dummies(df.episode_type, dtype=float).reindex(
        columns=EPISODE_TYPES, fill_value=0.0).to_numpy())
    parts.append((pd.get_dummies(df.market, dtype=float).to_numpy() * df.t.to_numpy()[:, None]))
    return np.hstack(parts)


def _slot_index(df: pd.DataFrame) -> np.ndarray:
    return df.groupby(["market", "date", "slot"]).ngroup().to_numpy()


def _softmax_out(u: np.ndarray, sid: np.ndarray, n: int) -> np.ndarray:
    """Shares with an outside option of utility 0, per slot id."""
    mx = np.maximum(np.zeros(n), np.full(n, -np.inf))
    np.maximum.at(mx, sid, u)
    e = np.exp(u - mx[sid])
    den = np.exp(-mx)
    np.add.at(den, sid, e)
    return e / den[sid], np.exp(-mx) / den


def fit_logit(X, s_obs, sid, l2=1e-3):
    from scipy.optimize import minimize
    n = sid.max() + 1
    s_out = 1 - np.bincount(sid, weights=s_obs, minlength=n)
    mu, sd = X.mean(0), X.std(0) + 1e-9
    Z = (X - mu) / sd

    def nll(w):
        u = Z @ w[1:] + w[0]
        s, s0 = _softmax_out(u, sid, n)
        loss = -(s_obs * np.log(s)).sum() - (s_out * np.log(s0)).sum() + l2 * (w[1:] ** 2).sum()
        tot = np.bincount(sid, weights=s_obs, minlength=n) + s_out  # = 1
        resid = s * tot[sid] - s_obs
        grad = np.concatenate([[resid.sum()], Z.T @ resid]) + np.concatenate([[0], 2 * l2 * w[1:]])
        return loss / n, grad / n

    w = minimize(nll, np.zeros(Z.shape[1] + 1), jac=True, method="L-BFGS-B",
                 options={"maxiter": 2000}).x
    return lambda Xn, sidn: _softmax_out(((Xn - mu) / sd) @ w[1:] + w[0], sidn, sidn.max() + 1)[0], w


def fit_neural_logit(X, s_obs, sid, hidden=32, epochs=60, lr=3e-3, l2=1e-4, seed=SEED):
    """Neurosymbolic share model: u = linear(x) + MLP(x), trained through the logit layer.

    The symbolic part (outside option, one softmax per slot, audience = pool x share) is fixed;
    the network only learns the utility. Plain NumPy with Adam, so no deep-learning framework.
    """
    rng = np.random.default_rng(seed)
    n = sid.max() + 1
    s_out = 1 - np.bincount(sid, weights=s_obs, minlength=n)
    mu, sd = X.mean(0), X.std(0) + 1e-9
    Z = (X - mu) / sd
    d = Z.shape[1]
    P = {"w": np.zeros(d), "b": np.zeros(1), "W1": rng.normal(0, 1 / np.sqrt(d), (d, hidden)),
         "b1": np.zeros(hidden), "W2": rng.normal(0, 0.01, hidden)}
    M = {k: np.zeros_like(v) for k, v in P.items()}; V = {k: np.zeros_like(v) for k, v in P.items()}
    slots = np.arange(n)
    step = 0
    for ep in range(epochs):
        rng.shuffle(slots)
        for chunk in np.array_split(slots, max(1, n // 512)):
            mask = np.isin(sid, chunk)
            z, so = Z[mask], s_obs[mask]
            _, sidc = np.unique(sid[mask], return_inverse=True)
            nc = sidc.max() + 1
            h = np.tanh(z @ P["W1"] + P["b1"])
            u = z @ P["w"] + P["b"][0] + h @ P["W2"]
            s, _ = _softmax_out(u, sidc, nc)
            tot = np.bincount(sidc, weights=so, minlength=nc) + (1 - np.bincount(sidc, weights=so, minlength=nc))
            r = (s * tot[sidc] - so) / nc
            gh = np.outer(r, P["W2"]) * (1 - h ** 2)
            G = {"w": z.T @ r + 2 * l2 * P["w"], "b": np.array([r.sum()]),
                 "W2": h.T @ r + 2 * l2 * P["W2"], "W1": z.T @ gh + 2 * l2 * P["W1"], "b1": gh.sum(0)}
            step += 1
            for k in P:
                M[k] = 0.9 * M[k] + 0.1 * G[k]; V[k] = 0.999 * V[k] + 0.001 * G[k] ** 2
                P[k] -= lr * (M[k] / (1 - 0.9 ** step)) / (np.sqrt(V[k] / (1 - 0.999 ** step)) + 1e-8)

    def predict(Xn, sidn):
        zn = (Xn - mu) / sd
        u = zn @ P["w"] + P["b"][0] + np.tanh(zn @ P["W1"] + P["b1"]) @ P["W2"]
        return _softmax_out(u, sidn, sidn.max() + 1)[0]
    return predict


POOL_NUM = ["pool_lag7", "pool_lag_mean", "slot_max_hype", "slot_sum_hype", "dow",
            "doy_sin", "doy_cos", "holiday", "slot_idx"]


def fit_pool(tr: pd.DataFrame, te: pd.DataFrame):
    def slots(d):
        s = d.groupby(["market", "date", "slot"]).first().reset_index()
        X = pd.concat([s[POOL_NUM].astype(float), pd.get_dummies(s.market, dtype=float)], axis=1)
        return s, X
    s_tr, X_tr = slots(tr)
    s_te, X_te = slots(te)
    # Like the channel models, the pool model predicts the log change from its 4-week level.
    p = fit_xgb(X_tr, np.log(s_tr.pool) - s_tr.pool_lag_mean, X_te)
    s_te["pool_hat"] = np.exp(s_te.pool_lag_mean + p)
    return te.join(s_te.set_index(["market", "date", "slot"]).pool_hat, on=["market", "date", "slot"]).pool_hat.to_numpy()


# --- Mistral Timestral (time-series foundation model) ------------------------------------------

TIMESTRAL_MODEL = os.environ.get("TIMESTRAL_MODEL", "mistralai/Timestral-209M")


def run_timestral(df: pd.DataFrame, te: pd.DataFrame) -> np.ndarray | None:
    """Zero-shot forecasts from Mistral's Timestral, 7 days ahead, for every test row.

    For each forecast origin (target date minus 7 days) the context of each channel-slot series is
    its full log-audience history up to the origin. We read the median of step 7. Needs the
    `timestral` package (pip install git+https://github.com/mistralai/timestral) and access to the
    weights on the Hugging Face Hub; returns None when either is missing.
    """
    try:
        from timestral import TimestralForecaster
        fc = TimestralForecaster.from_pretrained(TIMESTRAL_MODEL)
    except Exception as e:  # package, torch or weights unavailable
        print(f"Timestral not run: {type(e).__name__}: {e}")
        return None
    wide = df.pivot_table(index="date", columns=["channel", "slot"], values="log_aud")
    out = pd.Series(np.nan, index=te.index)
    for target in sorted(te.date.unique()):
        origin = target - pd.Timedelta(days=HORIZON)
        ctx = wide.loc[:origin].to_numpy().T[:, None, :]          # (series, 1 variate, time)
        f = fc.forecast(ctx, prediction_length=HORIZON)
        med = pd.Series(np.asarray(f.median)[:, 0, HORIZON - 1], index=wide.columns)
        rows = te.index[te.date == target]
        out[rows] = [med[(c, s)] for c, s in zip(te.channel[rows], te.slot[rows])]
    return np.exp(out.to_numpy())


# --- Nixtla HierarchicalForecast reconciliation -------------------------------------------------

def reconcile_mint(te: pd.DataFrame, aud_hat: np.ndarray, other_hat: np.ndarray, pool_hat: np.ndarray) -> np.ndarray:
    """Make channel forecasts add up with the pool: pool = sum(channels) + other (MinTrace, OLS)."""
    from hierarchicalforecast.core import HierarchicalReconciliation
    from hierarchicalforecast.methods import MinTrace
    d = te[["market", "slot", "channel", "date"]].copy()
    d["y_hat"] = aud_hat
    slot_keys = te.groupby(["market", "slot"]).size().index
    rows, S_rows, bottoms = [], [], []
    for m, h in slot_keys:
        chans = sorted(te[(te.market == m)].channel.unique())
        bottoms += [f"{m}/{h}/{c}" for c in chans] + [f"{m}/{h}/other"]
    tops = [f"{m}/{h}" for m, h in slot_keys]
    S = pd.DataFrame(0.0, index=tops + bottoms, columns=bottoms)
    for b in bottoms:
        S.loc[b, b] = 1.0
        S.loc[b.rsplit("/", 1)[0], b] = 1.0
    d["unique_id"] = d.market + "/" + d.slot.astype(str) + "/" + d.channel
    oth = te.groupby(["market", "slot", "date"]).size().reset_index()[["market", "slot", "date"]]
    oth = oth.merge(pd.DataFrame({"market": te.market, "slot": te.slot, "date": te.date,
                                  "o": other_hat, "p": pool_hat}).drop_duplicates(["market", "slot", "date"]))
    Yh = pd.concat([
        d[["unique_id", "date", "y_hat"]],
        pd.DataFrame({"unique_id": oth.market + "/" + oth.slot.astype(str) + "/other", "date": oth.date, "y_hat": oth.o}),
        pd.DataFrame({"unique_id": oth.market + "/" + oth.slot.astype(str), "date": oth.date, "y_hat": oth.p}),
    ]).rename(columns={"date": "ds", "y_hat": "XGB"})
    tags = {"slot": np.array(tops), "slot/channel": np.array(bottoms)}
    S_df = S.reset_index().rename(columns={"index": "unique_id"})
    rec = HierarchicalReconciliation(reconcilers=[MinTrace(method="wls_struct")]).reconcile(
        Y_hat_df=Yh, S_df=S_df, tags=tags)
    col = [c for c in rec.columns if c.startswith("XGB/")][0]
    rec = rec.set_index(["unique_id", "ds"])[col]
    return rec.reindex(pd.MultiIndex.from_arrays([d.unique_id, d.date])).to_numpy()


# ----------------------------------------------------------------------------- evaluation

def wape(y, yhat):
    return float(np.abs(y - yhat).sum() / np.abs(y).sum())


def evaluate(te: pd.DataFrame, preds: dict[str, np.ndarray]) -> dict:
    y = te.audience.to_numpy()
    sid = _slot_index(te)
    masks = {"all": np.ones(len(te), bool), "big_show": te.big_show.to_numpy(),
             "clash": (te.big_show & (te.rival_big | (te.n_same_genre > 0))).to_numpy()}
    days = te.date.to_numpy()
    uniq_days = np.unique(days)
    day_rows = {d: np.flatnonzero(days == d) for d in uniq_days}
    res = {}
    for name, p in preds.items():
        ok = ~np.isnan(p)
        r = {}
        for mk, m in masks.items():
            mm = m & ok
            r[f"wape_{mk}"] = wape(y[mm], p[mm]) if mm.any() else None
            r[f"n_{mk}"] = int(mm.sum())
        # Bootstrap over days (95% interval) for the big-show WAPE.
        big = masks["big_show"] & ok
        bs, diff_all, diff_big = [], [], []
        ref = preds["xgb_rival"]
        brng = np.random.default_rng(SEED)  # same resamples for every model: paired comparison
        for _ in range(500):
            pick_all = np.concatenate([day_rows[d] for d in brng.choice(uniq_days, len(uniq_days))])
            pick_all = pick_all[ok[pick_all]]
            pick = pick_all[big[pick_all]]
            bs.append(wape(y[pick], p[pick]))
            diff_big.append(wape(y[pick], p[pick]) - wape(y[pick], ref[pick]))
            diff_all.append(wape(y[pick_all], p[pick_all]) - wape(y[pick_all], ref[pick_all]))
        r["wape_big_show_ci"] = [float(np.percentile(bs, 2.5)), float(np.percentile(bs, 97.5))]
        r["diff_vs_xgb_rival_all_ci"] = [float(np.percentile(diff_all, 2.5)), float(np.percentile(diff_all, 97.5))]
        r["diff_vs_xgb_rival_big_ci"] = [float(np.percentile(diff_big, 2.5)), float(np.percentile(diff_big, 97.5))]
        # Slot winner: which channel has the largest audience in each slot.
        dfw = pd.DataFrame({"sid": sid, "y": y, "p": np.where(ok, p, -np.inf), "big": te.slot_max_hype.to_numpy() > 0})
        win_true = dfw.loc[dfw.groupby("sid").y.idxmax()].index
        win_pred = dfw.loc[dfw.groupby("sid").p.idxmax()].index
        hit = pd.Series(np.asarray(win_true) == np.asarray(win_pred))
        bigslot = dfw.groupby("sid").big.first().to_numpy()
        r["winner_acc_all"] = float(hit.mean())
        r["winner_acc_event_slots"] = float(hit[bigslot].mean())
        # Coherence: share of slots where the channel forecasts exceed the observed TV usage.
        tot = np.bincount(sid, weights=np.where(ok, p, 0))
        r["slots_over_pool"] = float((tot > te.groupby(sid).pool.first().to_numpy()).mean())
        res[name] = r
    return res


# ----------------------------------------------------------------------------- figures

COLORS = {"naive": "#8c8b85", "xgb": "#2a78d6", "xgb_rival": "#6250d6", "dnn": "#eb6834", "timestral": "#e87ba4",
          "jcs": "#1baf7a", "ns_jcs": "#008300", "xgb_mint": "#eda100"}
LABELS = {"naive": "Seasonal naive", "xgb": "XGBoost", "xgb_rival": "XGBoost + rivals", "dnn": "DNN (MLP)",
          "timestral": "Mistral Timestral", "jcs": "JCS", "ns_jcs": "Neurosymbolic JCS",
          "xgb_mint": "XGBoost + rivals + MinT"}


def figures(te, preds, res):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.dates  # noqa: F401
    import matplotlib.pyplot as plt
    plt.rcParams.update({"font.size": 9, "axes.spines.top": False, "axes.spines.right": False,
                         "axes.grid": True, "grid.color": "#e4e3dd", "grid.linewidth": 0.6,
                         "axes.edgecolor": "#8c8b85", "axes.axisbelow": True})
    FIG.mkdir(parents=True, exist_ok=True)
    names = [n for n in LABELS if n in res and res[n]["wape_all"] is not None]

    fig, axes = plt.subplots(1, 3, figsize=(9.5, 3.2), sharey=True)
    for ax, (k, title) in zip(axes, [("wape_all", "All slots"), ("wape_big_show", "Big shows"),
                                     ("wape_clash", "Big shows in contested slots")]):
        vals = [100 * res[n][k] for n in names]
        y = np.arange(len(names))
        ax.barh(y, vals, color=[COLORS[n] for n in names], height=0.6)
        if k == "wape_big_show":
            lo = [100 * res[n]["wape_big_show_ci"][0] for n in names]
            hi = [100 * res[n]["wape_big_show_ci"][1] for n in names]
            ax.errorbar(vals, y, xerr=[np.subtract(vals, lo), np.subtract(hi, vals)], fmt="none",
                        ecolor="#3d3d3a", elinewidth=0.8, capsize=2)
        ends = vals if k != "wape_big_show" else [100 * res[n]["wape_big_show_ci"][1] for n in names]
        for yi, v, e in zip(y, vals, ends):
            ax.text(e + 0.6, yi, f"{v:.1f}", va="center", fontsize=8, color="#3d3d3a")
        ax.set_title(title, fontsize=9, loc="left")
        ax.set_xlabel("WAPE (%)")
        ax.grid(axis="y", visible=False)
    axes[0].set_yticks(np.arange(len(names)), [LABELS[n] for n in names])
    axes[0].invert_yaxis()
    fig.tight_layout()
    fig.savefig(FIG / "wape.png", dpi=200)
    plt.close(fig)

    # Big-show forecasts: predicted vs actual, independent XGBoost against JCS.
    big = te.big_show.to_numpy()
    fig, axes = plt.subplots(1, 2, figsize=(7, 3.3), sharex=True, sharey=True)
    lim = [0.1, te.audience[big].max() * 1.15]
    for ax, n in zip(axes, ["xgb", "jcs"]):
        ax.scatter(te.audience[big], preds[n][big], s=10, color=COLORS[n], alpha=0.7,
                   edgecolor="white", linewidth=0.4)
        ax.plot(lim, lim, color="#8c8b85", lw=1, ls="--")
        ax.set_xscale("log"); ax.set_yscale("log"); ax.set_xlim(lim); ax.set_ylim(lim)
        ax.set_title(f"{LABELS[n]}: WAPE {100 * res[n]['wape_big_show']:.1f}%", fontsize=9, loc="left")
        ax.set_xlabel("Actual audience (millions)")
    axes[0].set_ylabel("Forecast (millions)")
    fig.tight_layout()
    fig.savefig(FIG / "big_shows_scatter.png", dpi=200)
    plt.close(fig)

    # One contested week in the simulated BR market at 21h.
    sel = te[(te.market == "BR") & (te.slot == 21)]
    week_start = sel[sel.big_show & sel.rival_big].date.min()
    if pd.isna(week_start):
        week_start = sel[sel.big_show].date.min()
    w = sel[(sel.date >= week_start - pd.Timedelta(days=3)) & (sel.date <= week_start + pd.Timedelta(days=10))]
    fig, axes = plt.subplots(1, 3, figsize=(9.5, 2.8), sharey=True)
    for ax, ch in zip(axes, sorted(w.channel.unique())):
        ww = w[w.channel == ch]
        idx = ww.index
        pos = te.index.get_indexer(idx)
        ax.plot(ww.date, ww.audience, color="#3d3d3a", lw=2, label="actual")
        for n in ["xgb", "dnn", "jcs"]:
            ax.plot(ww.date, preds[n][pos], color=COLORS[n], lw=1.4, label=LABELS[n])
        for d in ww[ww.hype > 0].date:
            ax.axvline(d, color="#c3c2b7", lw=6, alpha=0.5, zorder=0)
        ax.set_title(ch, fontsize=9, loc="left")
        ax.xaxis.set_major_formatter(matplotlib.dates.DateFormatter("%d %b"))
        ax.tick_params(axis="x", rotation=45, labelsize=7)
    axes[0].set_ylabel("Audience (millions)")
    axes[-1].legend(fontsize=7, frameon=False, loc="upper right")
    fig.tight_layout()
    fig.savefig(FIG / "contested_week.png", dpi=200)
    plt.close(fig)


# ----------------------------------------------------------------------------- main

def main():
    rng = np.random.default_rng(SEED)
    raw = simulate(seed=SEED)
    df = build_features(raw, rng)
    tr, te = df[df.date < TEST_START].reset_index(drop=True), df[df.date >= TEST_START].reset_index(drop=True)
    print(f"train rows {len(tr)}, test rows {len(te)}, test big shows {int(te.big_show.sum())}")

    preds = {"naive": np.exp(te.lag7).to_numpy()}  # same channel and slot, one week earlier
    t0 = time.time()
    # Independent models predict the log audience relative to the channel-slot's 4-week level.
    ytr = tr.log_aud - tr.lag_mean
    Xtr = design(tr, False); Xte = design(te, False).reindex(columns=Xtr.columns, fill_value=0)
    preds["xgb"] = np.exp(te.lag_mean + fit_xgb(Xtr, ytr, Xte)).to_numpy()
    Xtr_r = design(tr, True); Xte_r = design(te, True).reindex(columns=Xtr_r.columns, fill_value=0)
    preds["xgb_rival"] = np.exp(te.lag_mean + fit_xgb(Xtr_r, ytr, Xte_r)).to_numpy()
    preds["dnn"] = np.exp(te.lag_mean + fit_dnn(Xtr, ytr, Xte)).to_numpy()
    print(f"independent models {time.time() - t0:.0f}s")

    m = run_timestral(df, te)
    if m is not None:
        preds["timestral"] = m

    pool_hat = fit_pool(tr, te)
    Str, Ste = share_design(tr), share_design(te)
    sid_tr, sid_te = _slot_index(tr), _slot_index(te)
    logit, _ = fit_logit(Str, tr.share.to_numpy(), sid_tr)
    preds["jcs"] = pool_hat * logit(Ste, sid_te)
    nlogit = fit_neural_logit(Str, tr.share.to_numpy(), sid_tr)
    preds["ns_jcs"] = pool_hat * nlogit(Ste, sid_te)
    print(f"JCS models {time.time() - t0:.0f}s")

    # Nixtla reconciliation: an "other" forecast (pool minus the three channels) closes the hierarchy.
    tr_o = tr.groupby(["market", "date", "slot"]).first().reset_index()
    te_o = te.groupby(["market", "date", "slot"]).first().reset_index()
    tr_o["other"] = np.log(tr_o.pool * tr_o.outside); te_o["other"] = 0.0
    Xo_tr = pd.concat([tr_o[POOL_NUM].astype(float), pd.get_dummies(tr_o.market, dtype=float)], axis=1)
    Xo_te = pd.concat([te_o[POOL_NUM].astype(float), pd.get_dummies(te_o.market, dtype=float)], axis=1)
    te_o["other_hat"] = np.exp(te_o.pool_lag_mean + fit_xgb(Xo_tr, tr_o.other - tr_o.pool_lag_mean, Xo_te))
    other_hat = te.join(te_o.set_index(["market", "date", "slot"]).other_hat, on=["market", "date", "slot"]).other_hat.to_numpy()
    preds["xgb_mint"] = reconcile_mint(te, preds["xgb_rival"], other_hat, pool_hat)

    res = evaluate(te, preds)
    meta = {"seed": SEED, "train_rows": len(tr), "test_rows": len(te),
            "test_big_shows": int(te.big_show.sum()), "test_slots": int(sid_te.max() + 1),
            "timestral_run": "timestral" in preds, "timestral_model": TIMESTRAL_MODEL,
            "true_clash": 0.45, "share_features": SHARE_NUM}
    (ROOT / "results.json").write_text(json.dumps({"meta": meta, "results": res}, indent=2))
    write_md(meta, res)
    figures(te, preds, res)
    print(json.dumps(res, indent=1))


def write_md(meta, res):
    lines = ["# Results (simulated data)", "",
             "Generated by `python3 tv-audience/python/experiment.py`. Synthetic data only.", "",
             f"Test: {meta['test_rows']} channel-slots, {meta['test_slots']} slots, "
             f"{meta['test_big_shows']} big shows (2026-01-01 to 2026-10-31).", "",
             "| Model | WAPE all | WAPE big shows (95% CI) | WAPE contested | Winner acc. | Winner acc. event slots | Slots over pool |",
             "|---|---|---|---|---|---|---|"]
    diff = ["", "Paired day-bootstrap 95% interval of the WAPE difference against XGBoost + rivals "
            "(percentage points; below zero means better):", "",
            "| Model | All slots | Big shows |", "|---|---|---|"]
    for n in LABELS:
        if n not in res:
            lines.append(f"| {LABELS[n]} | not run | not run | not run | not run | not run | not run |")
            continue
        r = res[n]
        ci = r["wape_big_show_ci"]
        lines.append(f"| {LABELS[n]} | {100 * r['wape_all']:.1f}% | {100 * r['wape_big_show']:.1f}% "
                     f"({100 * ci[0]:.1f} to {100 * ci[1]:.1f}) | {100 * r['wape_clash']:.1f}% | "
                     f"{100 * r['winner_acc_all']:.1f}% | {100 * r['winner_acc_event_slots']:.1f}% | "
                     f"{100 * r['slots_over_pool']:.1f}% |")
        a, b = r["diff_vs_xgb_rival_all_ci"], r["diff_vs_xgb_rival_big_ci"]
        if n != "xgb_rival":
            diff.append(f"| {LABELS[n]} | {100 * a[0]:+.1f} to {100 * a[1]:+.1f} | {100 * b[0]:+.1f} to {100 * b[1]:+.1f} |")
    (ROOT / "results.md").write_text("\n".join(lines + diff) + "\n")


if __name__ == "__main__":
    main()
