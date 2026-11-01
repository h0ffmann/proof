---
title: 'Reference log for "Calm surface, fat tails"'
status: draft
date: 2026-11-01
---

# Reference log

Every entry in [`refs.bib`](refs.bib) was fetched before it was cited. This log records what was
checked and how, so a reviewer can repeat the check. `tools/fabric refs-check` fails when a
`refs.bib` key has no row here, or a row's key is not in `refs.bib`.

Status values: `verified` (source fetched, details match), `partial` (source fetched, a detail
could not be confirmed), `unverified` (not fetched; must not be cited).

| Key | Status | Checked against | Note |
|---|---|---|---|
| taleb2020scoft | verified | arXiv abstract page 2001.10488, 2026-11-01 | title, sole author, v1 24 Jan 2020, v4 17 Sep 2025 "Third Revised Edition", DOI 10.48550/arXiv.2001.10488 |
| hill1975tail | partial | Scilit record for DOI 10.1214/aos/1176343247, 2026-11-01 | title, journal, volume 3, issue 5, pages 1163-1174, 1975 and DOI match; the record did not show the author, and Project Euclid blocked the fetch |
| weissman1978quantiles | partial | CRAN ReIns `Quant` reference list, 2026-11-01 | author, title, JASA 73, 812-815, 1978 match; the publisher page (DOI 10.1080/01621459.1978.10480051) blocked the fetch, so the DOI is not confirmed |
