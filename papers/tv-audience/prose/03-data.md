# A simulated benchmark {#sec:data}

**Every audience number in this section and in [@Sec:results] is synthetic.** The generator,
`tv-audience/python/simulate.py`, follows [@eq:split] and [@eq:logit] with known parameters. A
simulation lets us check each model against a known truth before we spend real data on it. It
also has a cost: a model that matches the generator's structure has an advantage that real data
may not give it. [@Sec:discussion] returns to this.

## Markets, channels and slots

The benchmark has three markets, labelled UK, US and BR, with three channels each. The channel
names (UK-1 to BR-3) are placeholders, not real broadcasters. Each day has three one-hour prime-time
slots, at 20h, 21h and 22h. The data run from 2 January 2023 to 31 October 2026.

| Market | Mean pool (millions) | Mean shares of channels 1, 2, 3 | Mean outside share | Test big shows |
|---|---|---|---|---|
| UK | 15.1 | 0.28, 0.15, 0.12 | 0.46 | 39 |
| US | 50.3 | 0.17, 0.19, 0.17 | 0.47 | 43 |
| BR | 33.9 | 0.37, 0.13, 0.11 | 0.39 | 47 |

: The simulated markets. UK has a clear leader, US three near-equal networks, BR one dominant
channel. {#tbl:markets}

## How the generator works

**The pool.** The pool of each slot starts from a market level (18, 60 and 40 million viewers at
21h on an average 2023 weekday). Multipliers set the hour (0.90, 1.00, 0.80), the day of the week
(0.88 on Saturday to 1.04 on Sunday), the season (plus or minus 10% in UK and US, 6% in BR with a
mid-year peak) and the year-end holidays (0.85). Linear viewing falls by 3.5% a year. A big show
raises the pool by $0.35 \log(1 + \text{strength})$.

**Programmes.** Each channel and slot rotates six series in 13-week seasons. A series has a genre
(news, drama, reality, sport, comedy or film), a base appeal and an appeal loss per season.
Genres have a different appeal at each hour.

**Big shows.** Each channel airs about 31 events a year: premieres, finales, specials and live
finals. Event strength is log-normal with a heavy right tail, capped at 4. A *big show* is an
event with strength of at least 0.8; in the test period it has a median audience 2.2 times the
channel's usual audience in that hour. Channels also counter-program: when two events fall in the
same slot, the weaker one moves 1 to 3 days later with probability 0.5.

**Shares.** The utility of a channel adds its brand, the genre appeal at that hour, the series
appeal, $0.9 \log(1 + \text{strength})$ for an event, a lead-in term from the channel's share in
the previous hour, and a penalty of 0.45 for each rival that airs the same genre. The outside
option starts at utility 0.9 and gains 0.08 to 0.12 a year, as streaming takes viewers. Each
audience gets a 6% multiplicative noise.

**What the models see.** Forecasts are made 7 days ahead, the lead time of a published schedule.
A model sees the line-up of every channel (genre, episode type), audiences and pools at least 7
days old, the calendar, and a *hype* signal for each event. Hype is
$\log(1 + \text{strength})$ plus Gaussian noise with standard deviation 0.35. It stands for
pre-broadcast signals such as trailers, social media buzz or a previous season's finale. The
panel reports the pool with a 2% error. The models never see the true strengths, the series
appeal or the same-night lead-in.

## Train and test split

We train on 6 February 2023 to 31 December 2025 (the first five weeks only feed the lag features)
and test on 1 January to 31 October 2026. That gives 28,620 training and 8,208 test channel-slots,
in 2,736 test slots. The test set has 129 big shows. 46 of them air in a contested slot.
