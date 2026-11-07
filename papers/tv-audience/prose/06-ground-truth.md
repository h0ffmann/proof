# From simulation to real channels: a ground-truth protocol {#sec:groundtruth}

A simulation can rank models but cannot prove that they work on real viewers. Minute-level panel
data are licensed, but each of the three markets below publishes a free summary of its ratings.
That is enough for an honest test of big shows: freeze a forecast before the show airs, wait for
the published number, and score.

## Nine channels with public ratings

| Market | Channel | Public source of the actual audience | Metric | Published |
|---|---|---|---|---|
| UK | BBC One | Barb, weekly top 50 programmes [@barb2026top50] | consolidated 7-day average audience | weekly |
| UK | ITV1 | same | same | weekly |
| UK | Channel 4 | same | same | weekly |
| US | ABC | Nielsen, Top 10 linear TV, broadcast [@nielsen2026topten] | P2+ average audience and household rating | weekly |
| US | CBS | same | same | weekly |
| US | NBC | same | same | weekly |
| BR | Globo | Kantar IBOPE Media, weekly top 10 per channel [@meio2016ibope] | reach, individual and household audience, 15 markets | weekly, on Tuesday, for the week before |
| BR | Record | same | same | same |
| BR | SBT | same | same | same |

: Channels with published audience figures, three per market. {#tbl:channels}

We checked each source on 7 November 2026, except the Kantar IBOPE ranking. The Barb dashboard
covers "all broadcast channels and SVOD services" each week, with broadcast data from 27 August
2018 [@barb2026top50]. Nielsen's page listed ABC, CBS and NBC programmes in its broadcast top 10
for the week of 26 October to 1 November 2026, six days before our check [@nielsen2026topten].
For Brazil we found only the 2016 announcement: Kantar IBOPE Media began to publish, every
Tuesday, the top 10 programmes of Band, Globo, Record, RedeTV! and SBT across its 15 measured
markets [@meio2016ibope]. **We did not confirm that this ranking is still published in 2026.** A
reader should check it before relying on it. Brazilian newspapers also report Kantar's
preliminary ratings for Grande São Paulo the morning after a show; those numbers are a weaker
fallback, because they are preliminary and cover one city.

## Protocol: score after 14 days

1. **Freeze.** Seven days before a big show airs, run every model on the published line-ups of
   all channels in the slot. Commit the forecasts to the repository. The commit time stamps them.
2. **Wait.** Barb's figure for a show includes 7 days of catch-up viewing, so it cannot exist
   before day 7. Nielsen showed a week's list 6 days after it ended. Kantar IBOPE publishes on
   the Tuesday after the week, at most 9 days after broadcast. We score every forecast on day
   14 after broadcast, which covers all three sources with a margin.
3. **Score.** Compare each forecast with the published number. Report WAPE and winner accuracy
   per market, as in [@Sec:results].

Two caveats apply. First, the public lists are top-$N$ lists. A big show usually makes the list,
but a weak rival in the same slot may not, so the protocol scores big shows well and their rivals
poorly. Second, the three sources measure different things: 7-day consolidated viewers in the UK,
live-plus-same-day viewers in the US lists, and audience over 15 markets in Brazil. Each
market's models must be trained on the same metric they are scored on.
