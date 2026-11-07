---
title: 'Reference log for "Who wins the slot?"'
status: draft
date: 2026-11-07
---

# Reference log

Every entry in [`refs.bib`](refs.bib) was fetched before it was cited. This log records what was
checked and how, so a reviewer can repeat the check. `tools/fabric refs-check` fails when a
`refs.bib` key has no row here, or a row's key is not in `refs.bib`.

Status values: `verified` (source fetched, details match), `partial` (source fetched, a detail
could not be confirmed), `unverified` (not fetched; must not be cited).

| Key | Status | Checked against | Note |
|---|---|---|---|
| chen2016xgboost | verified | arXiv abstract page 1603.02754, 2026-11-07 | title, two authors, 2016, DOI 10.1145/2939672.2939785 |
| gruver2023llmtime | verified | arXiv abstract page 2310.07820, 2026-11-07 | title, four authors, v1 11 Oct 2023, comment "NeurIPS 2023", method: values written as digit strings |
| jiang2023mistral | verified | arXiv abstract page 2310.06825, 2026-11-07 | title, first three of 18 authors, 10 Oct 2023 |
| mistral2026timestral | partial | GitHub mistralai/timestral README and Hugging Face page mistralai/Timestral-28M, 2026-11-07 | four sizes 5M to 209M, 21 quantiles, 32,768-step context, past, known-future and categorical covariates, weights from the Hugging Face Hub, code Apache-2.0, weights Modified MIT; no release date or paper given, so the year is the access year |
| wickramasuriya2019mint | partial | Crossref API record for DOI 10.1080/01621459.2018.1448825, 2026-11-07 | title, three authors, JASA 114(526), 804-819 match; Crossref gives 2018 as the issued (online) year, the bib uses 2019, the volume year; the publisher page blocked the fetch |
| olivares2022hierarchicalforecast | verified | arXiv abstract page 2207.03517, 2026-11-07; GitHub Nixtla/hierarchicalforecast, 2026-11-07 | title, eight authors, submitted 7 Jul 2022; methods BottomUp, TopDown, MiddleOut, MinTrace, ERM; Apache-2.0 |
| garza2023timegpt | verified | arXiv abstract page 2310.03589, 2026-11-07 | title, three authors, v1 5 Oct 2023, zero-shot foundation model for time series |
| garcez2020neurosymbolic | verified | arXiv abstract page 2012.05876, 2026-11-07 | title, two authors, 10 Dec 2020 |
| rust1984audience | partial | Crossref API record for DOI 10.1287/mksc.3.2.113, 2026-11-07 | title, authors Rust and Alpert, Marketing Science 3(2), 113-124, 1984 match; the record gave family names only, the given names come from the author's standard citation; the content (lead-in, audience flow) was not read, the publisher page blocked the fetch |
| berry1994estimating | partial | Crossref API record for DOI 10.2307/2555829, 2026-11-07 | title, author, RAND Journal of Economics 25(2), 1994 match; Crossref gave only the first page, 242, so the last page is not confirmed |
| nixtla2026statsforecast | verified | GitHub Nixtla/statsforecast, 2026-11-07 | description "Lightning fast forecasting with statistical and econometric models", Apache-2.0 |
| nixtla2026mlforecast | verified | GitHub Nixtla/mlforecast, 2026-11-07 | scalable ML forecasting, XGBoost and LightGBM, lags and rolling transforms, exogenous variables, Apache-2.0 |
| nixtla2026neuralforecast | verified | GitHub Nixtla/neuralforecast, 2026-11-07 | more than 30 models including NHITS, TFT and PatchTST, exogenous and static covariates, Apache-2.0 |
| barb2026top50 | verified | Barb pages viewing-data/as-viewed-top-50 and viewing-data/most-viewed-programmes, 2026-11-07 | weekly top 50 across all broadcast channels and SVOD, consolidated 7-day figures, broadcast data from 27 Aug 2018; the pages did not state access terms |
| nielsen2026topten | verified | Nielsen data center page top-ten, 2026-11-07 | linear lists ranked on P2+ average audience, household rating; broadcast list for 26 Oct to 1 Nov 2026 shows ABC, CBS, NBC and FOX programmes |
| meio2016ibope | verified | Meio & Mensagem article, 2026-11-07 | author Guilherme Fernandes, 13 Jul 2016; weekly top 10 per channel for Band, Globo, Record, RedeTV! and SBT across 15 markets, published on Tuesdays; whether it continues in 2026 was not checked |
