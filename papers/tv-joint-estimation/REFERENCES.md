---
title: 'Reference log for "When is it worth estimating a TV slot''s channels together?"'
status: draft
date: 2026-11-11
---

# Reference log

Every entry in [`refs.bib`](refs.bib) was fetched before it was cited. The first eight rows are
copied from the reference logs of `papers/tv-audience/` and `papers/bandit-decision-layer/`, with
the date of their own check; the last two were fetched for this paper.

Status values: `verified` (source fetched, details match), `partial` (source fetched, a detail
could not be confirmed), `unverified` (not fetched; must not be cited).

| Key | Status | Checked against | Note |
|---|---|---|---|
| chen2016xgboost | verified | arXiv abstract page 1603.02754, 2026-11-07 | title, two authors, 2016, DOI 10.1145/2939672.2939785 |
| wickramasuriya2019mint | partial | Crossref API record for DOI 10.1080/01621459.2018.1448825, 2026-11-07 | title, three authors, JASA 114(526), 804-819 match; Crossref gives 2018 as the issued (online) year, the bib uses 2019, the volume year; the publisher page blocked the fetch |
| berry1994estimating | partial | Crossref API record for DOI 10.2307/2555829, 2026-11-07 | title, author, RAND Journal of Economics 25(2), 1994 match; Crossref gave only the first page, 242, so the last page is not confirmed |
| rust1984audience | partial | Crossref API record for DOI 10.1287/mksc.3.2.113, 2026-11-07 | title, authors Rust and Alpert, Marketing Science 3(2), 113-124, 1984 match; the record gave family names only, the given names come from the author's standard citation; the content (lead-in, audience flow) was not read, the publisher page blocked the fetch |
| barb2026top50 | verified | Barb pages viewing-data/as-viewed-top-50 and viewing-data/most-viewed-programmes, 2026-11-07 | weekly top 50 across all broadcast channels and SVOD, consolidated 7-day figures, broadcast data from 27 Aug 2018; the pages did not state access terms |
| nielsen2026topten | verified | Nielsen data center page top-ten, 2026-11-07 | linear lists ranked on P2+ average audience, household rating; broadcast list for 26 Oct to 1 Nov 2026 shows ABC, CBS, NBC and FOX programmes |
| meio2016ibope | verified | Meio & Mensagem article, 2026-11-07 | author Guilherme Fernandes, 13 Jul 2016; weekly top 10 per channel for Band, Globo, Record, RedeTV! and SBT across 15 markets, published on Tuesdays; whether it continues in 2026 was not checked |
| agda2025safe | partial | the page at the URL, 2026-11-11 | the page lists the features that `--safe` refuses, `postulate` first; the year of the 2.8.0 release is not on the page |
| panagiotelis2021geometric | verified | Crossref API record and Semantic Scholar abstract for DOI 10.1016/j.ijforecast.2020.06.004, 2026-11-11 | title, four authors, IJF 37(1), 343-359, 2021; the abstract states that reconciliation by projection is guaranteed to improve accuracy for a class of distance-based losses, and that MinT minimises expected loss in that class |
| hyndman2011optimal | verified | Crossref API record and Semantic Scholar abstract for DOI 10.1016/j.csda.2011.03.006, 2026-11-11 | title, four authors, CSDA 55(9), 2579-2589, 2011; the abstract proposes forecasting every level independently and then combining them by regression |
