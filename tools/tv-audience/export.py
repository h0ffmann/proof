"""Write the test rows that the seasonal-naive check needs, from tv-audience/python as it is.

It runs `simulate` and `build_features` of tv-audience/python/experiment.py with the same seed,
so the rows are the ones the experiment scores, and writes one CSV row per channel-slot of the
test period. No model is trained here: the seasonal naive forecast is the audience of the same
channel and slot 7 days before (`np.exp(te.lag7)`), and that is the forecast the tool scores.

    python3 tools/tv-audience/export.py OUT.csv
"""

import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tv-audience" / "python"))
from experiment import SEED, TEST_START, _slot_index, build_features  # noqa: E402
from simulate import simulate  # noqa: E402


def main(out: str) -> None:
    rng = np.random.default_rng(SEED)
    df = build_features(simulate(seed=SEED), rng)
    te = df[df.date >= TEST_START].reset_index(drop=True)
    te = te.assign(sid=_slot_index(te), day=(te.date - TEST_START).dt.days,
                   naive=np.exp(te.lag7),
                   clash=te.big_show & (te.rival_big | (te.n_same_genre > 0)),
                   event=te.slot_max_hype > 0)
    cols = ["sid", "day", "audience", "naive", "pool", "big_show", "clash", "event"]
    with open(out, "w") as f:
        f.write(",".join(cols) + "\n")
        for r in te[cols].itertuples(index=False):
            f.write(f"{r.sid},{r.day},{r.audience!r},{r.naive!r},{r.pool!r},"
                    f"{int(r.big_show)},{int(r.clash)},{int(r.event)}\n")


if __name__ == "__main__":
    main(sys.argv[1])
