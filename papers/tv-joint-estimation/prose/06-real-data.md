# Public ratings: what can be tested now {#sec:real}

A simulation can check a method against a known truth, but it cannot say how often
$|\varepsilon| \le |S|$ holds for real viewers. Minute-level panel data are licensed. Three
markets publish free summaries, and the repository has a Haskell pipeline that reads them.

**The pipeline.** `tools/tv-ratings/` fetches Nielsen's weekly Top 10 of linear TV in the US
[@nielsen2026topten], with viewers aged 2 and over and the household rating, and three Wikipedia
lists of most watched broadcasts (UK, US and Brazilian telenovelas) at pinned revisions, so two
fetches give the same rows. It reads their HTML tables with GHC's bundled libraries only, refuses
a page whose expected table or column is missing, and writes one CSV row per published figure,
with its source, list, period, rank, programme, channel, metric and unit. Its self-test runs the
parsers on pages written for the test. Two sources of our earlier protocol are not wired: the
Barb top 50 [@barb2026top50] loads its table from an API whose terms the page does not state,
and the Kantar IBOPE Media site [@meio2016ibope] answered HTTP 403 on 11 November 2026. The
fetched files are not committed, because the pages change and each has its own terms.

**Why the identity cannot be tested on these data yet.** Theorem 2 is about a slot: every channel
of one market in one hour, its forecast and the pool. The public lists give neither. They are
top-$N$ lists, so a weak rival in a big show's slot is often missing, and no source gives the air
time, so the rows of one week cannot be put into slots. Neither $S$ nor $\varepsilon$ can be
computed. What the lists do give is the actual audience of big shows, which is the quantity a
frozen forecast would be scored against.

**A protocol.** Freeze, seven days before a big show, a forecast of every channel of its slot and
of the pool, and commit it; the commit time stamps it. Score it on day 14 after broadcast, when
the three markets' figures exist (Barb's include 7 days of catch-up viewing). For the slots where
every channel and the pool are published, $S$, $\varepsilon$ and both sides of [@eq:gain] can
then be computed. Each market measures something different (7-day consolidated viewers in the UK,
live and same-day viewers in the US lists, Grande São Paulo points in the Brazilian list), so each
market's models must be trained on the metric they are scored on. This test has not been run.
