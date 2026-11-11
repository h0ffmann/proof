"""Run tv-audience/python/experiment.py as it is, and write what it computed for the Haskell pipeline.

No line of the experiment is copied here. `experiment.main()` runs unchanged; this script wraps
four of its functions to keep their arguments and results, and points its output folder at OUT:

  evaluate        the test rows and every model's forecasts, as the experiment scores them
  fit_logit       the JCS share design, the observed shares and the fitted weights
  fit_neural_logit  the neurosymbolic JCS; its parameters are read from the closure it returns
  fit_pool, reconcile_mint  the pool forecast and the "other" forecast of each test row
  figures         replaced by nothing (no Matplotlib is needed)

Nixtla's hierarchicalforecast is not in the pinned nixpkgs. When its import fails, the MinT arm
gets no forecast and is left out of the scores, as the experiment leaves out Timestral; the
pipeline computes that reconciliation in closed form instead.

    python3 tools/tv-validate/export.py OUT

OUT gets test.csv, panel.csv, share_train.csv, share_test.csv, model.json, bootstrap.csv, and the
experiment's own results.json and results.md of this run.
"""

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tv-audience" / "python"))
import experiment as ex  # noqa: E402

cap: dict = {}


def closure(fn) -> dict:
    return dict(zip(fn.__code__.co_freevars, (c.cell_contents for c in fn.__closure__)))


def wrap(name: str):
    def deco(new):
        orig = getattr(ex, name)
        setattr(ex, name, lambda *a, **k: new(orig, *a, **k))
        return new
    return deco


@wrap("evaluate")
def _evaluate(orig, te, preds):
    # An arm with no forecast is left out, as the experiment leaves out Timestral when it did not run.
    preds = {k: v for k, v in preds.items() if not np.isnan(v).all()}
    cap["te"], cap["preds"] = te, preds
    return orig(te, preds)


@wrap("fit_logit")
def _fit_logit(orig, X, s_obs, sid, l2=1e-3):
    predict, w = orig(X, s_obs, sid, l2)
    cap["logit"] = {"X": X, "s_obs": s_obs, "sid": sid, "l2": l2, "w": w}
    return predict, w


@wrap("fit_neural_logit")
def _fit_neural_logit(orig, X, s_obs, sid, **kw):
    predict = orig(X, s_obs, sid, **kw)
    cap["ns"] = closure(predict)
    return predict


@wrap("fit_pool")
def _fit_pool(orig, tr, te):
    cap["pool_hat"] = orig(tr, te)
    return cap["pool_hat"]


@wrap("reconcile_mint")
def _reconcile_mint(orig, te, aud_hat, other_hat, pool_hat):
    cap["other_hat"] = other_hat
    try:
        out = orig(te, aud_hat, other_hat, pool_hat)
        cap["mint_run"] = True
    except ImportError as e:
        print(f"MinT not run: {e}")
        out = np.full(len(te), np.nan)
        cap["mint_run"] = False
    return out


@wrap("share_design")
def _share_design(orig, df):
    cap.setdefault("designs", []).append(orig(df))
    return cap["designs"][-1]


@wrap("build_features")
def _build_features(orig, raw, rng):
    cap["df"] = orig(raw, rng)
    return cap["df"]


ex.figures = lambda *a, **k: None


def write_csv(path: Path, cols: dict) -> None:
    """One column per key; floats with repr, so that Haskell reads back the same Double."""
    def cell(v):
        if isinstance(v, (bool, np.bool_)):
            return "1" if v else "0"
        if isinstance(v, (float, np.floating)):
            return repr(float(v))
        return str(v)
    with open(path, "w") as f:
        f.write(",".join(cols) + "\n")
        for row in zip(*cols.values()):
            f.write(",".join(cell(v) for v in row) + "\n")


def main(out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    ex.ROOT = out
    ex.main()
    te, preds, df = cap["te"], cap["preds"], cap["df"]

    res = json.loads((out / "results.json").read_text())
    res["meta"]["mint_run"] = cap["mint_run"]
    res["meta"]["versions"] = {m.__name__: m.__version__ for m in
                               (np, pd, __import__("scipy"), __import__("sklearn"), __import__("xgboost"))}
    res["meta"]["python"] = sys.version.split()[0]
    (out / "results.json").write_text(json.dumps(res, indent=2))

    day = lambda d: (d - ex.TEST_START).dt.days  # noqa: E731
    cols = {
        "sid": ex._slot_index(te), "day": day(te.date), "market": te.market, "channel": te.channel,
        "slot": te.slot, "audience": te.audience, "pool": te.pool,
        "big": te.big_show, "clash": te.big_show & (te.rival_big | (te.n_same_genre > 0)),
        "event": te.slot_max_hype > 0, "lag7": te.lag7, "lag_mean": te.lag_mean,
        "pool_hat": cap["pool_hat"], "other_hat": cap["other_hat"],
    }
    cols.update({f"p_{k}": v for k, v in preds.items()})
    write_csv(out / "test.csv", cols)

    # Every row of the panel the features were built from, for the checks of the lags.
    write_csv(out / "panel.csv", {"market": df.market, "channel": df.channel, "slot": df.slot,
                                  "day": day(df.date), "audience": df.audience})

    lg = cap["logit"]
    d = lg["X"].shape[1]
    tr_design, te_design = cap["designs"]
    assert tr_design is lg["X"] or np.array_equal(tr_design, lg["X"])
    write_csv(out / "share_train.csv", {"sid": lg["sid"], "s_obs": lg["s_obs"],
                                        **{f"x{j}": lg["X"][:, j] for j in range(d)}})
    write_csv(out / "share_test.csv", {"sid": cols["sid"],
                                       **{f"x{j}": te_design[:, j] for j in range(d)}})

    ns = cap["ns"]
    P = ns["P"]
    model = {
        "logit": {"w": lg["w"].tolist(), "l2": lg["l2"]},
        "ns": {"w": P["w"].tolist(), "b": float(P["b"][0]), "W1": P["W1"].tolist(),
               "b1": P["b1"].tolist(), "W2": P["W2"].tolist(),
               "mu": ns["mu"].tolist(), "sd": ns["sd"].tolist()},
    }
    (out / "model.json").write_text(json.dumps(model))

    # The day resamples of evaluate's bootstrap: the same generator, seed and calls.
    days = np.unique(te.date.to_numpy())
    brng = np.random.default_rng(ex.SEED)
    with open(out / "bootstrap.csv", "w") as f:
        for _ in range(500):
            pick = brng.choice(days, len(days))
            f.write(",".join(str(int(i)) for i in np.searchsorted(days, pick)) + "\n")
    print(f"exported {len(te)} test rows, {len(lg['sid'])} train rows, {d} share features to {out}")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())
