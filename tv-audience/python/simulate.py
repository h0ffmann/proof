"""Simulated prime-time TV audiences for three markets with three competing channels each.

Every number this module produces is synthetic. The generator is a structural model of slot
competition: a market-level pool of viewers (total TV usage) is split between the channels and an
outside option (all other channels and streaming) by a nested-logit choice rule. Big shows pull
extra viewers into the pool and take share from rivals; two shows of the same genre in the same slot
cannibalise each other. The forecasting models in `experiment.py` never see the latent variables,
only what a broadcaster's planner would know a week ahead.

Run `python3 tv-audience/python/experiment.py`; it calls `simulate()` with a fixed seed.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

GENRES = ["news", "drama", "reality", "sport", "comedy", "film"]
EPISODE_TYPES = ["regular", "premiere", "finale", "special", "live_final"]

# Synthetic markets. Channel names are placeholders, not real broadcasters.
# pool: TV-set viewers in millions in the 21h slot of an average 2023 weekday (TV usage);
# brand: channel intercepts in the share utility (leader, challenger, third).
MARKETS = {
    "UK": {"pool": 18.0, "brand": [0.55, 0.25, -0.35], "streaming_drift": 0.10},
    "US": {"pool": 60.0, "brand": [0.30, 0.25, 0.15], "streaming_drift": 0.12},
    "BR": {"pool": 40.0, "brand": [0.95, 0.10, 0.00], "streaming_drift": 0.08},
}
SLOTS = [20, 21, 22]  # local start hour of each one-hour prime-time slot

# True genre appeal by slot hour (rows: GENRES, cols: SLOTS).
GENRE_APPEAL = np.array([
    [0.35, 0.05, -0.10],   # news
    [0.10, 0.30, 0.25],    # drama
    [0.05, 0.25, 0.15],    # reality
    [0.20, 0.30, 0.20],    # sport
    [0.15, 0.10, -0.05],   # comedy
    [-0.10, 0.05, 0.15],   # film
])

CLASH = 0.45        # utility penalty per same-genre rival in the slot (cannibalisation)
LEAD_IN = 0.9       # weight on the channel's own share in the previous slot (log-odds)
EVENT_POOL = 0.35   # how much a big show expands the market pool, per unit of strength
NOISE_SD = 0.06     # multiplicative audience noise (log scale)
HYPE_SD = 0.35      # noise of the observable pre-broadcast hype signal around true strength


def _series_catalogue(rng: np.random.Generator, n_channels: int) -> list[list[dict]]:
    """Recurring series for each channel and slot: genre, base appeal and a season calendar."""
    cat = []
    for c in range(n_channels):
        per_slot = []
        for s in range(len(SLOTS)):
            series = []
            for k in range(6):  # six series rotate through each slot over four years
                g = rng.choice(len(GENRES), p=[0.18, 0.28, 0.18, 0.10, 0.14, 0.12])
                if s == 0 and c == 0 and k < 3:
                    g = 0  # the leader runs news at 20h for long stretches
                series.append({
                    "id": f"c{c}s{s}k{k}",
                    "genre": int(g),
                    "appeal": float(rng.normal(0.0, 0.25)),
                    "decay": float(rng.uniform(0.0, 0.25)),  # appeal lost per season
                })
            per_slot.append(series)
        cat.append(per_slot)
    return cat


def simulate(seed: int = 20261107, start: str = "2023-01-02", end: str = "2026-10-31") -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    dates = pd.date_range(start, end, freq="D")
    rows = []
    for market, spec in MARKETS.items():
        brand = np.array(spec["brand"])
        n_ch = len(brand)
        cat = _series_catalogue(rng, n_ch)
        # Each series airs in 13-week seasons; the active series index per channel/slot changes
        # every season, with a random offset so channels do not change line-ups on the same day.
        offsets = rng.integers(0, 91, size=(n_ch, len(SLOTS)))
        # Big events: about 2.5 per channel per month, with heavy-tailed strength.
        n_days = len(dates)
        event = np.zeros((n_days, n_ch, len(SLOTS)))
        etype = np.zeros((n_days, n_ch, len(SLOTS)), dtype=int)
        for c in range(n_ch):
            n_ev = rng.poisson(0.085 * n_days)
            days = rng.integers(0, n_days, size=n_ev)
            slots = rng.choice(len(SLOTS), size=n_ev, p=[0.25, 0.45, 0.30])
            for d, s in zip(days, slots):
                event[d, c, s] = float(np.clip(rng.lognormal(-0.1, 0.55), 0.2, 4.0))
                etype[d, c, s] = int(rng.choice([1, 2, 3, 4], p=[0.3, 0.3, 0.2, 0.2]))
        # Strategic scheduling: a challenger moves its own big show away from a rival's bigger one
        # half the time (counter-programming), so clashes happen but less often than by chance.
        for d in range(n_days):
            for s in range(len(SLOTS)):
                live = np.flatnonzero(event[d, :, s])
                if len(live) > 1:
                    keep = live[np.argmax(event[d, live, s])]
                    for c in live:
                        if c != keep and rng.random() < 0.5:
                            nd = min(n_days - 1, d + int(rng.integers(1, 4)))
                            event[nd, c, s], etype[nd, c, s] = event[d, c, s], etype[d, c, s]
                            event[d, c, s], etype[d, c, s] = 0.0, 0
        sport_event = rng.random((n_days, n_ch, len(SLOTS))) < 0.5  # live finals are sport or reality

        for di, day in enumerate(dates):
            t = (day - dates[0]).days / 365.25
            dow = day.day_of_week
            week_mult = [1.00, 1.01, 1.02, 1.00, 0.95, 0.88, 1.04][dow]
            season_mult = 1.0 + 0.10 * np.cos(2 * np.pi * (day.day_of_year - 15) / 365.25)
            if market == "BR":  # southern hemisphere: winter peak mid-year
                season_mult = 1.0 + 0.06 * np.cos(2 * np.pi * (day.day_of_year - 196) / 365.25)
            holiday = 0.85 if (day.month == 12 and day.day >= 24) or (day.month == 1 and day.day == 1) else 1.0
            trend = np.exp(-0.035 * t)
            prev_share = brand_share = None
            for si, hour in enumerate(SLOTS):
                hour_mult = [0.90, 1.00, 0.80][si]
                info = []
                for c in range(n_ch):
                    season_idx = ((di + offsets[c, si]) // 91) % 6
                    ser = cat[c][si][season_idx]
                    season_no = (di + offsets[c, si]) // (91 * 6)
                    genre = ser["genre"]
                    strength = event[di, c, si]
                    ep = etype[di, c, si]
                    if ep == 4:
                        genre = GENRES.index("sport") if sport_event[di, c, si] else GENRES.index("reality")
                    info.append({"series": ser["id"], "genre": genre, "ep": ep, "strength": strength,
                                 "appeal": ser["appeal"] - ser["decay"] * season_no})
                genres = np.array([x["genre"] for x in info])
                strengths = np.array([x["strength"] for x in info])
                pool = (spec["pool"] * week_mult * season_mult * holiday * trend * hour_mult
                        * (1.0 + EVENT_POOL * np.log1p(strengths.max())))
                u = np.empty(n_ch)
                for c, x in enumerate(info):
                    same = int((genres == x["genre"]).sum() - 1)
                    u[c] = (brand[c] + GENRE_APPEAL[x["genre"], si] + x["appeal"]
                            + 0.9 * np.log1p(x["strength"]) - CLASH * same)
                    if prev_share is not None:
                        u[c] += LEAD_IN * (np.log(prev_share[c]) - np.log(brand_share[c]))
                u0 = 0.9 + spec["streaming_drift"] * t  # outside option gains on linear TV
                ex = np.exp(u)
                share = ex / (np.exp(u0) + ex.sum())
                aud = pool * share * np.exp(rng.normal(0.0, NOISE_SD, n_ch))
                for c, x in enumerate(info):
                    hype = (np.log1p(x["strength"]) + rng.normal(0, HYPE_SD)) if x["strength"] > 0 else 0.0
                    rows.append({
                        "market": market, "channel": f"{market}-{c + 1}", "ch_idx": c,
                        "date": day, "slot": hour, "slot_idx": si,
                        "series": x["series"], "genre": GENRES[x["genre"]],
                        "episode_type": EPISODE_TYPES[x["ep"]], "hype": float(max(hype, 0.0)),
                        "big_show": bool(x["strength"] >= 0.8),
                        "audience": float(aud[c]), "true_share": float(share[c]),
                        "true_pool": float(pool),
                    })
                if brand_share is None:
                    eb = np.exp(brand)
                    brand_share = eb / (np.exp(u0) + eb.sum())
                prev_share = share
    return pd.DataFrame(rows)


if __name__ == "__main__":
    df = simulate()
    print(df.groupby(["market", "channel"]).audience.describe().round(2))
    print("big-show share of rows:", round(df.big_show.mean(), 3))
